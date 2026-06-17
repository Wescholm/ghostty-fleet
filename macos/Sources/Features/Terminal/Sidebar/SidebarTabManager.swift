import Cocoa
import Combine

/// Observes the tab group of a window and publishes tab metadata for the sidebar.
@MainActor
class SidebarTabManager: ObservableObject {
    struct TabItem: Identifiable, Equatable {
        let id: ObjectIdentifier
        let title: String
        let pwd: String?
        let gitBranch: String?
        let surfaceId: UUID?
        let statusEntries: [TabMetadataStore.StatusEntry]
        let isSelected: Bool
        let needsAttention: Bool
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
                && lhs.surfaceId == rhs.surfaceId
                && lhs.statusEntries == rhs.statusEntries
                && lhs.needsAttention == rhs.needsAttention
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

    /// Cache of git branch keyed by pwd. Populated off the main thread by a
    /// background poll so refresh() never does filesystem I/O on the main thread.
    private var gitBranchCache: [String: String?] = [:]
    private var gitPollTask: Task<Void, Never>?

    init(window: NSWindow, bellTriggersAttention: Bool = true) {
        self.window = window
        self.bellTriggersAttention = bellTriggersAttention
        setupObservers()
        refresh()
        startGitPolling()
    }

    deinit {
        timer?.invalidate()
        gitPollTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

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

    // MARK: - Git Branch

    /// Read the git branch from .git/HEAD in the given directory.
    /// Walks up to find the repo root (supports subdirectories).
    /// `nonisolated static` so it can run off the main actor in the poll task.
    nonisolated private static func gitBranch(at pwd: String) -> String? {
        var dir = pwd
        while dir != "/" {
            let headPath = (dir as NSString).appendingPathComponent(".git/HEAD")
            if let contents = try? String(contentsOfFile: headPath, encoding: .utf8) {
                let prefix = "ref: refs/heads/"
                if contents.hasPrefix(prefix) {
                    return contents.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil // detached HEAD
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Periodically reads git branches for the current tabs off the main thread,
    /// updating the cache and re-publishing only when a branch actually changes.
    private func startGitPolling() {
        gitPollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let pwds = await self?.currentPwds() else { return }
                if !pwds.isEmpty {
                    var results: [String: String?] = [:]
                    for pwd in pwds {
                        if Task.isCancelled { return }
                        results[pwd] = SidebarTabManager.gitBranch(at: pwd)
                    }
                    await self?.applyGitBranches(results)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func currentPwds() -> Set<String> {
        Set(tabs.compactMap { $0.pwd })
    }

    private func applyGitBranches(_ results: [String: String?]) {
        var changed = false
        for (pwd, branch) in results {
            let existing = gitBranchCache[pwd]
            if existing == nil || existing! != branch {
                gitBranchCache[pwd] = branch
                changed = true
            }
        }
        if changed { refresh() }
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
            let branch = pwd.flatMap { gitBranchCache[$0] ?? nil }
            let color = (w as? TerminalWindow)?.tabColor ?? .none

            return TabItem(
                id: wid,
                title: w.title,
                pwd: pwd,
                gitBranch: branch,
                surfaceId: sid,
                statusEntries: entries,
                isSelected: w === selectedWindow,
                needsAttention: attentionWindows.contains(wid) && w !== selectedWindow,
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
