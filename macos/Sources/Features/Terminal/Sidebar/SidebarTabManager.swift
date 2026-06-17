import Cocoa
import Combine
import Darwin

/// Observes the tab group of a window and publishes tab metadata for the sidebar.
@MainActor
class SidebarTabManager: ObservableObject {
    struct TabItem: Identifiable, Equatable {
        let id: ObjectIdentifier
        let title: String
        let pwd: String?
        let gitBranch: String?
        let gitDirty: Bool
        let gitAhead: Int
        let gitBehind: Int
        let surfaceId: UUID?
        let statusEntries: [TabMetadataStore.StatusEntry]
        let isSelected: Bool
        let needsAttention: Bool
        let isWorking: Bool
        let tabColor: TerminalTabColor
        let window: NSWindow

        /// The last path component of the pwd, for compact display.
        var directoryName: String? {
            guard let pwd, !pwd.isEmpty else { return nil }
            return (pwd as NSString).lastPathComponent
        }

        /// Title with bell emoji stripped (the sidebar uses its own attention indicator).
        var displayTitle: String {
            title.hasPrefix("\u{1F514} ") ? String(title.dropFirst(3)) : title
        }

        static func == (lhs: TabItem, rhs: TabItem) -> Bool {
            lhs.id == rhs.id && lhs.title == rhs.title && lhs.isSelected == rhs.isSelected
                && lhs.pwd == rhs.pwd && lhs.gitBranch == rhs.gitBranch
                && lhs.gitDirty == rhs.gitDirty && lhs.gitAhead == rhs.gitAhead
                && lhs.gitBehind == rhs.gitBehind
                && lhs.surfaceId == rhs.surfaceId
                && lhs.statusEntries == rhs.statusEntries
                && lhs.needsAttention == rhs.needsAttention
                && lhs.isWorking == rhs.isWorking
                && lhs.tabColor == rhs.tabColor
        }
    }

    @Published var tabs: [TabItem] = []

    /// Windows that need attention, cleared when the tab is selected.
    private var attentionWindows: Set<ObjectIdentifier> = []

    /// Whether bells should trigger the sidebar attention indicator.
    /// Derived from `bell-features` containing `attention`.
    private let bellTriggersAttention: Bool

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    /// Cache of git info keyed by pwd. Populated off the main thread by a
    /// background poll so refresh() never does filesystem I/O on the main thread.
    private var gitInfoCache: [String: GitInfo] = [:]
    private var gitPollTask: Task<Void, Never>?

    /// CPU samples per surface id for activity detection: (cpu ns, pid, sample time).
    private var cpuSamples: [UUID: (cpu: UInt64, pid: Int, time: TimeInterval)] = [:]
    /// Last time each surface's foreground process was above the CPU threshold.
    private var lastBusy: [UUID: TimeInterval] = [:]
    /// Surfaces whose foreground process is actively using CPU ("working").
    private var workingSurfaces: Set<UUID> = []
    private var activityTimer: Timer?

    /// Keep a tab "working" for this long after its CPU dips, so brief gaps
    /// between tool calls don't flicker the indicator.
    private static let workingGracePeriod: TimeInterval = 2.5

    init(window: NSWindow, bellTriggersAttention: Bool = true) {
        self.window = window
        self.bellTriggersAttention = bellTriggersAttention
        setupObservers()
        refresh()
        startGitPolling()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sampleActivity()
        }
    }

    deinit {
        timer?.invalidate()
        activityTimer?.invalidate()
        gitPollTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

#if DEBUG
    /// Preview/testing only: a manager with fixed tabs and none of the live
    /// machinery (no window, observers, timers, or git polling).
    init(previewTabs: [TabItem]) {
        self.bellTriggersAttention = false
        self.tabs = previewTabs
    }
#endif

    private func setupObservers() {
        let center = NotificationCenter.default

        let titleObserver = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
        observers.append(titleObserver)

        let resignObserver = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
        observers.append(resignObserver)

        // Bell: respect bell-features config
        if bellTriggersAttention {
            let bellObserver = center.addObserver(
                forName: .terminalWindowBellDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let controller = notification.object as? BaseTerminalController,
                      let w = controller.window else { return }
                let hasBell = notification.userInfo?[Notification.Name.terminalWindowHasBellKey] as? Bool ?? false
                if hasBell {
                    self.markAttention(window: w)
                } else {
                    self.clearAttention(for: ObjectIdentifier(w))
                    self.refresh()
                }
            }
            observers.append(bellObserver)
        }

        // Desktop notifications (OSC 9/99, command completion): always trigger attention
        let desktopNotifObserver = center.addObserver(
            forName: .ghosttyDesktopNotificationDidFire,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView,
                  let w = surfaceView.window else { return }
            self.markAttention(window: w)
        }
        observers.append(desktopNotifObserver)

        // IPC notifications (tab.notify command): trigger attention
        let ipcNotifObserver = center.addObserver(
            forName: .ghosttyIPCNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let w = notification.object as? NSWindow else { return }
            self.markAttention(window: w)
        }
        observers.append(ipcNotifObserver)

        // Poll periodically for tab group changes, title changes, pwd changes, metadata changes.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Attention

    private func markAttention(window w: NSWindow) {
        // Don't mark attention for the currently selected tab — the user can already see it.
        let selected = window?.tabGroup?.selectedWindow ?? window
        guard w !== selected else { return }
        attentionWindows.insert(ObjectIdentifier(w))
        refresh()
    }

    private func clearAttention(for id: ObjectIdentifier) {
        attentionWindows.remove(id)
    }

    // MARK: - Git Info

    /// Branch, dirty state, and ahead/behind for a working directory.
    struct GitInfo: Equatable {
        var branch: String?
        var dirty: Bool
        var ahead: Int
        var behind: Int

        static let none = GitInfo(branch: nil, dirty: false, ahead: 0, behind: 0)
    }

    /// Read git info for a directory via `git status`. Worktree- and submodule-aware
    /// (unlike reading .git/HEAD directly). `nonisolated static` so it runs off the
    /// main actor in the poll task.
    nonisolated private static func gitInfo(at pwd: String) -> GitInfo {
        guard let out = runGit(["-C", pwd, "status", "--porcelain=v2", "--branch"]) else {
            return .none
        }
        var info = GitInfo.none
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# branch.head ") {
                let name = line.dropFirst("# branch.head ".count).trimmingCharacters(in: .whitespaces)
                info.branch = (name == "(detached)") ? nil : name
            } else if line.hasPrefix("# branch.ab ") {
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { info.ahead = Int(part.dropFirst()) ?? 0 }
                    else if part.hasPrefix("-") { info.behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if !line.hasPrefix("#") {
                info.dirty = true
            }
        }
        return info
    }

    /// Run a git command and return stdout, or nil on failure. Read-only and
    /// non-interactive (no credential prompts, no index locks).
    nonisolated private static func runGit(_ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        proc.environment = env
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Periodically reads git branches for the current tabs off the main thread,
    /// updating the cache and re-publishing only when a branch actually changes.
    private func startGitPolling() {
        gitPollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let pwds = await self?.currentPwds() else { return }
                if !pwds.isEmpty {
                    var results: [String: GitInfo] = [:]
                    for pwd in pwds {
                        if Task.isCancelled { return }
                        results[pwd] = SidebarTabManager.gitInfo(at: pwd)
                    }
                    await self?.applyGitInfo(results)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func currentPwds() -> Set<String> {
        Set(tabs.compactMap { $0.pwd })
    }

    private func applyGitInfo(_ results: [String: GitInfo]) {
        var changed = false
        for (pwd, info) in results {
            if gitInfoCache[pwd] != info {
                gitInfoCache[pwd] = info
                changed = true
            }
        }
        if changed { refresh() }
    }

    // MARK: - Activity

    /// Sample CPU usage of each tab's foreground process to detect which sessions
    /// are actively computing. proc_pidinfo is a fast syscall, so this runs on the
    /// main actor and re-publishes only when the working set changes.
    private func sampleActivity() {
        guard let window else { return }
        let tabWindows: [NSWindow]
        if let tabbedWindows = window.tabbedWindows, !tabbedWindows.isEmpty {
            tabWindows = tabbedWindows
        } else {
            tabWindows = [window]
        }

        let now = Date().timeIntervalSinceReferenceDate
        var newWorking: Set<UUID> = []
        var seen: Set<UUID> = []
        for w in tabWindows {
            guard let controller = w.windowController as? BaseTerminalController,
                  let surface = controller.focusedSurface else { continue }
            let sid = surface.id
            seen.insert(sid)
            guard let pid = surface.surfaceModel?.foregroundPID,
                  let cpu = Self.processCPUNanos(pid: pid) else {
                cpuSamples[sid] = nil
                continue
            }
            if let prev = cpuSamples[sid], prev.pid == pid, now > prev.time {
                let cpuDelta = Double(cpu &- prev.cpu)
                let wallDelta = (now - prev.time) * 1_000_000_000
                let usage = wallDelta > 0 ? cpuDelta / wallDelta : 0  // fraction of one core
                if usage > 0.03 { lastBusy[sid] = now }
            }
            cpuSamples[sid] = (cpu, pid, now)
            if let busy = lastBusy[sid], now - busy < Self.workingGracePeriod {
                newWorking.insert(sid)
            }
        }
        cpuSamples = cpuSamples.filter { seen.contains($0.key) }
        lastBusy = lastBusy.filter { seen.contains($0.key) }

        if newWorking != workingSurfaces {
            workingSurfaces = newWorking
            refresh()
        }
    }

    /// Total CPU time (nanoseconds) consumed by a process, or nil if unavailable.
    nonisolated private static func processCPUNanos(pid: Int) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(Int32(pid), PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info.pti_total_user &+ info.pti_total_system
    }

    // MARK: - Refresh

    func refresh() {
        guard let window else { return }

        let tabWindows: [NSWindow]
        if let tabbedWindows = window.tabbedWindows, !tabbedWindows.isEmpty {
            tabWindows = tabbedWindows
        } else {
            tabWindows = [window]
        }

        let selectedWindow = window.tabGroup?.selectedWindow ?? window
        let metadataStore = TabMetadataStore.shared

        let newTabs = tabWindows.map { w -> TabItem in
            let controller = w.windowController as? BaseTerminalController
            let surface = controller?.focusedSurface
            let wid = ObjectIdentifier(w)
            let sid = surface?.id
            let pwd = surface?.pwd
            let entries = sid.map { metadataStore.statusEntries(for: $0) } ?? []
            let gitInfo = pwd.flatMap { gitInfoCache[$0] } ?? .none
            let color = (w as? TerminalWindow)?.tabColor ?? .none

            return TabItem(
                id: wid,
                title: w.title,
                pwd: pwd,
                gitBranch: gitInfo.branch,
                gitDirty: gitInfo.dirty,
                gitAhead: gitInfo.ahead,
                gitBehind: gitInfo.behind,
                surfaceId: sid,
                statusEntries: entries,
                isSelected: w === selectedWindow,
                needsAttention: attentionWindows.contains(wid) && w !== selectedWindow,
                isWorking: sid.map { workingSurfaces.contains($0) } ?? false,
                tabColor: color,
                window: w
            )
        }

        if newTabs != tabs {
            tabs = newTabs
        }
    }

    // MARK: - Tab Actions

    func selectTab(_ tab: TabItem) {
        clearAttention(for: tab.id)
        tab.window.makeKeyAndOrderFront(nil)
    }

    func setTabColor(_ color: TerminalTabColor, for tab: TabItem) {
        (tab.window as? TerminalWindow)?.tabColor = color
        refresh()
    }

    func closeTab(_ tab: TabItem) {
        guard let controller = tab.window.windowController as? TerminalController else { return }
        controller.closeTab(nil)
    }

    func renameTab(_ tab: TabItem, to newTitle: String) {
        guard let controller = tab.window.windowController as? BaseTerminalController else { return }
        controller.titleOverride = newTitle.isEmpty ? nil : newTitle
        refresh()
    }

    func promptRenameTab(_ tab: TabItem) {
        guard let controller = tab.window.windowController as? BaseTerminalController else { return }
        controller.promptTabTitle()
    }

    func closeOtherTabs(_ tab: TabItem) {
        guard let window else { return }
        let tabWindows: [NSWindow]
        if let tabbedWindows = window.tabbedWindows, !tabbedWindows.isEmpty {
            tabWindows = tabbedWindows
        } else {
            return
        }
        for w in tabWindows where ObjectIdentifier(w) != tab.id {
            if let controller = w.windowController as? TerminalController {
                controller.closeTab(nil)
            }
        }
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard let window else { return }
        guard let tabbedWindows = window.tabbedWindows, !tabbedWindows.isEmpty else { return }
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabbedWindows.count,
              destinationIndex >= 0, destinationIndex < tabbedWindows.count else { return }

        let movingWindow = tabbedWindows[sourceIndex]
        let targetWindow = tabbedWindows[destinationIndex]

        if sourceIndex > destinationIndex {
            targetWindow.addTabbedWindowSafely(movingWindow, ordered: .below)
        } else {
            targetWindow.addTabbedWindowSafely(movingWindow, ordered: .above)
        }

        if let selectedWindow = window.tabGroup?.selectedWindow {
            selectedWindow.makeKeyAndOrderFront(nil)
        }

        refresh()
    }

    func closeTabsToTheRight(of tab: TabItem) {
        guard let window else { return }
        let tabWindows: [NSWindow]
        if let tabbedWindows = window.tabbedWindows, !tabbedWindows.isEmpty {
            tabWindows = tabbedWindows
        } else {
            return
        }
        guard let idx = tabWindows.firstIndex(where: { ObjectIdentifier($0) == tab.id }) else { return }
        for w in tabWindows[(idx + 1)...] {
            if let controller = w.windowController as? TerminalController {
                controller.closeTab(nil)
            }
        }
    }
}
