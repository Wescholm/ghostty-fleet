import Foundation
import Cocoa
import UserNotifications
import OSLog

/// A Unix domain socket server that allows external processes to control Ghostty tabs.
///
/// Protocol: newline-delimited JSON over a Unix domain socket at `/tmp/ghostty-{uid}.sock`.
///
/// Request format:
/// ```json
/// {"method": "tab.rename", "params": {"tab_id": "optional-uuid", "title": "New Title"}}
/// ```
///
/// Response format:
/// ```json
/// {"ok": true, "result": {...}}
/// {"ok": false, "error": "message"}
/// ```
@MainActor
final class GhosttyIPCServer {
    static let shared = GhosttyIPCServer()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "IPC"
    )

    private var serverFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: ClientConnection] = [:]
    private var socketPath: String = ""

    /// Per-client state for buffering partial reads.
    private class ClientConnection {
        let fd: Int32
        var readSource: DispatchSourceRead?
        var buffer: Data = Data()

        init(fd: Int32) {
            self.fd = fd
        }
    }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        let uid = getuid()
        socketPath = "/tmp/ghostty-\(uid).sock"

        // Remove stale socket if it exists
        unlink(socketPath)

        // Create socket
        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            Self.logger.warning("IPC: failed to create socket: \(errno)")
            return
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Self.logger.warning("IPC: socket path too long")
            close(serverFd)
            serverFd = -1
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for i in 0..<pathBytes.count {
                    dest[i] = pathBytes[i]
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Self.logger.warning("IPC: failed to bind socket: \(errno)")
            close(serverFd)
            serverFd = -1
            return
        }

        // Set permissions to user-only
        chmod(socketPath, 0o600)

        // Listen
        guard Darwin.listen(serverFd, 5) == 0 else {
            Self.logger.warning("IPC: failed to listen: \(errno)")
            close(serverFd)
            serverFd = -1
            return
        }

        // Set non-blocking
        let flags = fcntl(serverFd, F_GETFL)
        fcntl(serverFd, F_SETFL, flags | O_NONBLOCK)

        // Accept loop via DispatchSource
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: .main)
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverFd, fd >= 0 {
                close(fd)
                self?.serverFd = -1
            }
        }
        source.resume()
        acceptSource = source

        Self.logger.info("IPC: listening on \(self.socketPath)")
    }

    func stop() {
        // Cancel accept source
        acceptSource?.cancel()
        acceptSource = nil

        // Disconnect all clients
        for (_, client) in clients {
            disconnectClient(client)
        }
        clients.removeAll()

        // Remove socket file
        if !socketPath.isEmpty {
            unlink(socketPath)
        }

        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }

        Self.logger.info("IPC: stopped")
    }

    // MARK: - Client Management

    private func acceptClient() {
        var addr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFd = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverFd, sockPtr, &len)
            }
        }
        guard clientFd >= 0 else { return }

        // Set non-blocking
        let flags = fcntl(clientFd, F_GETFL)
        fcntl(clientFd, F_SETFL, flags | O_NONBLOCK)

        let client = ClientConnection(fd: clientFd)

        let readSource = DispatchSource.makeReadSource(fileDescriptor: clientFd, queue: .main)
        readSource.setEventHandler { [weak self] in
            self?.readFromClient(clientFd)
        }
        readSource.setCancelHandler {
            close(clientFd)
        }
        readSource.resume()
        client.readSource = readSource

        clients[clientFd] = client
    }

    private func readFromClient(_ fd: Int32) {
        guard let client = clients[fd] else { return }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)

        if n <= 0 {
            // EOF or error — disconnect
            disconnectClient(client)
            clients.removeValue(forKey: fd)
            return
        }

        client.buffer.append(contentsOf: buf[0..<n])

        // Process complete lines
        while let newlineIndex = client.buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = client.buffer[client.buffer.startIndex..<newlineIndex]
            client.buffer.removeSubrange(client.buffer.startIndex...newlineIndex)

            guard !lineData.isEmpty else { continue }
            processRequest(data: Data(lineData), client: client)
        }

        // Guard against excessively large buffers (no newline after 1MB)
        if client.buffer.count > 1_048_576 {
            disconnectClient(client)
            clients.removeValue(forKey: fd)
        }
    }

    private func disconnectClient(_ client: ClientConnection) {
        client.readSource?.cancel()
        client.readSource = nil
    }

    // MARK: - Request Processing

    private func processRequest(data: Data, client: ClientConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else {
            sendError("invalid request: expected JSON with 'method' field", to: client)
            return
        }

        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "tab.rename":
            handleTabRename(params: params, client: client)
        case "tab.notify":
            handleTabNotify(params: params, client: client)
        case "tab.set-status":
            handleTabSetStatus(params: params, client: client)
        case "tab.clear-status":
            handleTabClearStatus(params: params, client: client)
        case "tab.list":
            handleTabList(client: client)
        case "tab.current":
            handleTabCurrent(client: client)
        case "tab.focus":
            handleTabFocus(params: params, client: client)
        default:
            sendError("unknown method: \(method)", to: client)
        }
    }

    // MARK: - Method Handlers

    private func handleTabRename(params: [String: Any], client: ClientConnection) {
        guard let title = params["title"] as? String else {
            sendError("tab.rename requires 'title' param", to: client)
            return
        }

        guard let target = resolveTarget(params: params) else {
            sendError("tab not found", to: client)
            return
        }

        // Per-session title (matches the sidebar's own rename) — so renaming a *background* session
        // updates that session's card, not the controller/window title of whatever is visible.
        target.session.titleOverride = title.isEmpty ? nil : title
        sendOk(["renamed": true], to: client)
    }

    private func handleTabNotify(params: [String: Any], client: ClientConnection) {
        let title = params["title"] as? String ?? "Ghostty"
        let body = params["body"] as? String ?? ""

        // macOS notification (shows as banner when app is not focused)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.warning("IPC: notification error: \(error)")
            }
        }

        // Sidebar attention indicator (visible when app is focused). Post the originating *surface*
        // (like `.ghosttyDesktopNotificationDidFire`) so the sidebar can attribute attention to the
        // owning session — including a background one — instead of just the active window (G1).
        if let target = resolveTarget(params: params) {
            NotificationCenter.default.post(
                name: .ghosttyIPCNotification,
                object: target.surface
            )
        }

        sendOk(["notified": true], to: client)
    }

    private func handleTabSetStatus(params: [String: Any], client: ClientConnection) {
        guard let key = params["key"] as? String,
              let value = params["value"] as? String else {
            sendError("tab.set-status requires 'key' and 'value' params", to: client)
            return
        }

        guard let target = resolveTarget(params: params) else {
            sendError("tab not found", to: client)
            return
        }

        // Keyed by session id (not surface id) so status set from any surface in the session — and
        // from a *background* session — lands on that session's card. The sidebar reads by session id.
        let icon = params["icon"] as? String
        TabMetadataStore.shared.setStatus(tabId: target.session.id, key: key, value: value, icon: icon)
        sendOk(["status_set": true], to: client)
    }

    private func handleTabClearStatus(params: [String: Any], client: ClientConnection) {
        guard let key = params["key"] as? String else {
            sendError("tab.clear-status requires 'key' param", to: client)
            return
        }

        guard let target = resolveTarget(params: params) else {
            sendError("tab not found", to: client)
            return
        }

        TabMetadataStore.shared.clearStatus(tabId: target.session.id, key: key)
        sendOk(["status_cleared": true], to: client)
    }

    private func handleTabList(client: ClientConnection) {
        var tabInfos: [[String: Any]] = []

        let keyWindow = NSApp.keyWindow

        // One entry per in-app session (not per window). Under the old native-tab model each window
        // was one tab; now a single window owns N sessions, and `ghosttyctl list` must surface all of
        // them — including background sessions — so an agent can discover and target them (G1).
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else { continue }
            let isKey = (window === keyWindow)
            for session in controller.sessions {
                guard let surface = representativeSurface(for: session, in: controller) else { continue }
                let isActive = isKey && session.id == controller.activeSession?.id
                tabInfos.append(tabInfo(
                    session: session,
                    surface: surface,
                    controller: controller,
                    window: window,
                    isActive: isActive
                ))
            }
        }

        sendOk(["tabs": tabInfos], to: client)
    }

    private func handleTabCurrent(client: ClientConnection) {
        guard let window = NSApp.keyWindow,
              let controller = window.windowController as? BaseTerminalController,
              let session = controller.activeSession,
              let surface = representativeSurface(for: session, in: controller) else {
            sendError("no active tab", to: client)
            return
        }

        sendOk(tabInfo(session: session, surface: surface, controller: controller, window: window, isActive: true), to: client)
    }

    private func handleTabFocus(params: [String: Any], client: ClientConnection) {
        guard let target = resolveTarget(params: params),
              let window = target.controller.window else {
            sendError("tab not found", to: client)
            return
        }
        // Bring the window forward first (covers the already-active-session case, where selectSession
        // is a no-op), then switch the in-app session to the one that owns the surface (G1: focus a
        // *background* session, not just raise a window). selectSession no-ops if already active.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let index = target.controller.sessions.firstIndex(where: { $0.id == target.session.id }) {
            target.controller.selectSession(at: index)
        }
        sendOk(["focused": true], to: client)
    }

    // MARK: - Tab Resolution

    /// A resolved IPC target: the controller, the in-app ``Session``, and the specific surface the
    /// `tab_id` matched. A "tab" is an in-app session (sidebar re-architecture); `tab_id` is a
    /// per-surface UUID (`GHOSTTY_TAB_ID`).
    private typealias Target = (controller: BaseTerminalController, session: Session, surface: Ghostty.SurfaceView)

    /// Resolve params to the targeted session. With `tab_id`, finds the session whose tree contains
    /// that surface across **every** session of **every** window — crucially including *background*
    /// (non-mounted) sessions, which is the whole point of G1: `ghosttyctl` must reach a session even
    /// when it isn't the visible one. Without `tab_id`, defaults to the key window's active session.
    private func resolveTarget(params: [String: Any]) -> Target? {
        if let tabIdStr = params["tab_id"] as? String,
           let tabId = UUID(uuidString: tabIdStr) {
            return resolve(surfaceId: tabId)
        }

        // Default: the key window's active session (and its focused surface).
        guard let controller = NSApp.keyWindow?.windowController as? BaseTerminalController,
              let session = controller.activeSession,
              let surface = controller.focusedSurface ?? session.surfaceTree.root?.leftmostLeaf() else {
            return nil
        }
        return (controller, session, surface)
    }

    /// Find the (controller, session, surface) owning a surface UUID — searching every session's
    /// split tree, not just the mounted one, so background sessions are reachable.
    private func resolve(surfaceId id: UUID) -> Target? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else { continue }
            for session in controller.sessions {
                for surface in session.surfaceTree where surface.id == id {
                    return (controller, session, surface)
                }
            }
        }
        return nil
    }

    /// The surface that represents a session for IPC (the one whose id becomes the listed `tab_id`).
    /// For the controller's active session this is the focused surface; otherwise the tree's leftmost
    /// leaf — matching how `SidebarTabManager` picks each card's representative surface.
    private func representativeSurface(for session: Session, in controller: BaseTerminalController) -> Ghostty.SurfaceView? {
        if session.id == controller.activeSession?.id, let focused = controller.focusedSurface {
            return focused
        }
        return session.surfaceTree.root?.leftmostLeaf()
    }

    // MARK: - Tab Info

    private func tabInfo(
        session: Session,
        surface: Ghostty.SurfaceView,
        controller: BaseTerminalController,
        window: NSWindow,
        isActive: Bool
    ) -> [String: Any] {
        // `tab_id` is the representative surface's id, so it round-trips back through
        // `resolve(surfaceId:)` for focus / set-status / rename.
        var info: [String: Any] = [
            "tab_id": surface.id.uuidString,
            "title": session.titleOverride ?? (surface.title.isEmpty ? window.title : surface.title),
            "is_active": isActive,
        ]
        if let pwd = surface.pwd {
            info["pwd"] = pwd
        }
        if let pid = surface.surfaceModel?.foregroundPID {
            info["foreground_pid"] = pid
        }
        return info
    }

    // MARK: - Response Helpers

    private func sendOk(_ result: [String: Any], to client: ClientConnection) {
        let response: [String: Any] = ["ok": true, "result": result]
        sendJSON(response, to: client)
    }

    private func sendError(_ message: String, to client: ClientConnection) {
        let response: [String: Any] = ["ok": false, "error": message]
        sendJSON(response, to: client)
    }

    private func sendJSON(_ obj: [String: Any], to client: ClientConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        let bytes = Array(line.utf8)
        bytes.withUnsafeBufferPointer { buf in
            var written = 0
            while written < buf.count {
                let n = write(client.fd, buf.baseAddress! + written, buf.count - written)
                if n <= 0 { break }
                written += n
            }
        }
    }
}
