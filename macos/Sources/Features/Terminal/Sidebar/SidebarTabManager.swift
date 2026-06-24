import Cocoa
import Combine
import Darwin

/// Observes a controller's in-app ``Session``s and publishes tab metadata for the sidebar.
///
/// Sidebar re-architecture (Step 5): the data source is now the controller's `sessions` (one split
/// tree each), not native `NSWindow` tabs. The git-polling, CPU-activity, and `TabMetadataStore`
/// status machinery is unchanged — only the source of `TabItem`s and the tab actions moved from
/// windows → sessions.
@MainActor
class SidebarTabManager: ObservableObject {
    struct TabItem: Identifiable, Equatable {
        /// The owning ``Session``'s stable id. Survives reorder/rename and surface swaps.
        let id: UUID
        let title: String
        let pwd: String?
        let gitBranch: String?
        let gitDirty: Bool
        let gitAhead: Int
        let gitBehind: Int
        let surfaceId: UUID?
        let statusEntries: [TabMetadataStore.StatusEntry]
        let isSelected: Bool
        /// The single effective lifecycle status rendered as the card's status dot. Merges the
        /// agent-reported `Session.status` with the CPU "working" and bell/notify "attention" signals
        /// (see ``effectiveStatus(reported:attention:working:)``). `.idle` ⇒ no dot.
        let status: SessionStatus
        let tabColor: TerminalTabColor

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
                && lhs.status == rhs.status
                && lhs.tabColor == rhs.tabColor
        }
    }

    @Published var tabs: [TabItem] = []

    /// Sessions that need attention, keyed by ``Session/id``, cleared when the session is selected.
    private var attentionSessions: Set<UUID> = []

    /// Whether bells should trigger the sidebar attention indicator.
    /// Derived from `bell-features` containing `attention`.
    private let bellTriggersAttention: Bool

    /// The controller whose sessions back this sidebar.
    private weak var controller: BaseTerminalController?

    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
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

    init(controller: BaseTerminalController, bellTriggersAttention: Bool = true) {
        self.controller = controller
        self.bellTriggersAttention = bellTriggersAttention
        setupObservers()
        observeController(controller)
        startPolling() // refreshes + starts the refresh/CPU/git pollers (occlusion-gated, audit M6)
    }

    deinit {
        timer?.invalidate()
        activityTimer?.invalidate()
        gitPollTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

#if DEBUG
    /// Preview/testing only: a manager with fixed tabs and none of the live
    /// machinery (no controller, observers, timers, or git polling).
    init(previewTabs: [TabItem]) {
        self.bellTriggersAttention = false
        self.tabs = previewTabs
    }
#endif

    /// Subscribe to the controller's published session state so the sidebar re-renders when sessions
    /// are added/removed/reordered or the active session changes. `objectWillChange` fires *before*
    /// the change, so refresh on the next runloop turn to read the new value.
    private func observeController(_ controller: BaseTerminalController) {
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
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

        // Bell → attention, per-session (respects the bell-features config). G2: use the per-surface
        // `.ghosttyBellDidRing` notification, which carries the *originating surface* (object), instead
        // of the controller-level `.terminalWindowBellDidChangeNotification`. The controller aggregate
        // only watches the *mounted* tree (`surfaceValuesPublisher` over `$surfaceTree`), so a bell in
        // a background session was invisible to it; the per-surface signal fires regardless of which
        // session the surface lives in, so attention attributes to the right card — including a
        // background one — exactly like desktop notifications.
        if bellTriggersAttention {
            let bellObserver = center.addObserver(
                forName: .ghosttyBellDidRing,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
                self.markAttention(sessionId: self.sessionId(for: surfaceView))
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
                  let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
            self.markAttention(sessionId: self.sessionId(for: surfaceView))
        }
        observers.append(desktopNotifObserver)

        // IPC notifications (tab.notify command): trigger attention
        let ipcNotifObserver = center.addObserver(
            forName: .ghosttyIPCNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
            // The IPC notification now carries the originating surface (G1), so attribute attention to
            // the owning session — including a background one — exactly like desktop notifications.
            self.markAttention(sessionId: self.sessionId(for: surfaceView))
        }
        observers.append(ipcNotifObserver)

        // Pause the pollers when the window is fully occluded / minimized / on another Space, per
        // Apple's "Work When Visible" energy guidance (audit M6): nothing on screen ⇒ no refresh, CPU
        // sampling, or git subprocesses. Re-arm (and immediately refresh) when it becomes visible again.
        let occlusionObserver = center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let window = note.object as? NSWindow,
                  window == self.controller?.window else { return }
            if window.occlusionState.contains(.visible) {
                self.startPolling()
            } else {
                self.suspendPolling()
            }
        }
        observers.append(occlusionObserver)
    }

    /// (Re)start the three pollers — 0.5 s refresh, 1 s CPU-activity sample, and the git-status poll —
    /// after tearing down any existing ones, plus one immediate refresh so the UI is current. Called at
    /// init and whenever the window becomes visible again (audit M6).
    private func startPolling() {
        suspendPolling()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sampleActivity()
        }
        startGitPolling()
    }

    /// Stop the pollers while the window isn't visible (audit M6).
    private func suspendPolling() {
        timer?.invalidate(); timer = nil
        activityTimer?.invalidate(); activityTimer = nil
        gitPollTask?.cancel(); gitPollTask = nil
    }

    // MARK: - Attention

    /// Find the session that owns the given surface, if any.
    private func sessionId(for surface: Ghostty.SurfaceView?) -> UUID? {
        guard let surface, let controller else { return nil }
        return controller.sessions.first(where: { $0.surfaceTree.contains(surface) })?.id
    }

    private func markAttention(sessionId: UUID?) {
        guard let sessionId else { return }
        // Don't mark attention for the currently selected session — the user can already see it.
        guard sessionId != controller?.activeSession?.id else { return }
        attentionSessions.insert(sessionId)
        refresh()
    }

    private func clearAttention(for id: UUID) {
        attentionSessions.remove(id)
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
        // Drop cache entries for pwds no longer shown so the cache can't grow unbounded over a long
        // session of opening/closing many directories (audit L8).
        let live = currentPwds()
        if gitInfoCache.count > live.count {
            gitInfoCache = gitInfoCache.filter { live.contains($0.key) }
        }
        if changed { refresh() }
    }

    // MARK: - Activity

    /// The surface that represents a session in the sidebar (its single visible/dot-bearing surface).
    /// For the active session this is the focused surface; otherwise the tree's leftmost leaf.
    private func representativeSurface(for session: Session, at index: Int) -> Ghostty.SurfaceView? {
        let focused = (index == controller?.activeSessionIndex) ? controller?.focusedSurface : nil
        return focused ?? session.surfaceTree.root?.leftmostLeaf()
    }

    /// Sample CPU usage of each session's representative foreground process to detect which sessions
    /// are actively computing. proc_pidinfo is a fast syscall, so this runs on the main actor and
    /// re-publishes only when the working set changes.
    private func sampleActivity() {
        guard let controller else { return }

        let now = Date().timeIntervalSinceReferenceDate
        var newWorking: Set<UUID> = []
        var seen: Set<UUID> = []
        for (i, session) in controller.sessions.enumerated() {
            guard let surface = representativeSurface(for: session, at: i) else { continue }
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

    /// Mach timebase (numer/denom) for converting `proc_taskinfo` CPU times — which are in Mach
    /// absolute-time units, *not* nanoseconds — into nanoseconds. On Apple Silicon the tick is ~24 MHz
    /// (numer/denom ≈ 125/3), so the raw value is ~41× too small; without this conversion the "working"
    /// CPU heuristic's threshold was never reached and the dot never lit on Apple Silicon.
    nonisolated private static let machTimebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    /// Total CPU time (nanoseconds) consumed by a process, or nil if unavailable.
    nonisolated private static func processCPUNanos(pid: Int) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(Int32(pid), PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        let ticks = info.pti_total_user &+ info.pti_total_system
        let tb = Self.machTimebase
        return ticks &* UInt64(tb.numer) / UInt64(tb.denom)
    }

    // MARK: - Status

    /// Merge the layered status signals into the single value the card's dot shows. Precedence
    /// (chosen with the user): **attention > error > waiting > running > done > idle**. `attention`
    /// is the bell/notify flag; `working` is the foreground-CPU heuristic (counts as running and
    /// outranks a stale done/idle); `reported` is the agent-authoritative `Session.status` set over
    /// IPC (`ghosttyctl state …`, e.g. from Claude Code hooks).
    static func effectiveStatus(reported: SessionStatus, attention: Bool, working: Bool) -> SessionStatus {
        if attention || reported == .attention { return .attention }
        if reported == .error { return .error }
        if reported == .waiting { return .waiting }
        if reported == .running { return .running }
        if working { return .running }
        if reported == .done { return .done }
        return .idle
    }

    // MARK: - Refresh

    func refresh() {
        guard let controller else { return }

        let metadataStore = TabMetadataStore.shared
        let activeId = controller.activeSession?.id

        // Whatever made a session active — sidebar tap, Cmd+T, or an IPC `tab.focus` that bypasses
        // selectTab — clears its pending attention, so a stale dot can't reappear on switch-away.
        if let activeId { attentionSessions.remove(activeId) }

        let newTabs = controller.sessions.enumerated().map { (i, session) -> TabItem in
            let surface = representativeSurface(for: session, at: i)
            let sid = surface?.id
            let pwd = surface?.pwd
            let title = session.titleOverride ?? surface?.title ?? ""
            // Status is keyed by session id (set via IPC `tab.set-status`), so it follows the session
            // across surface swaps/splits and shows for background sessions too (G1).
            let entries = metadataStore.statusEntries(for: session.id)
            let gitInfo = pwd.flatMap { gitInfoCache[$0] } ?? .none
            let isSelected = i == controller.activeSessionIndex
            let color = session.tabColor ?? .none

            return TabItem(
                id: session.id,
                title: title,
                pwd: pwd,
                gitBranch: gitInfo.branch,
                gitDirty: gitInfo.dirty,
                gitAhead: gitInfo.ahead,
                gitBehind: gitInfo.behind,
                surfaceId: sid,
                statusEntries: entries,
                isSelected: isSelected,
                status: Self.effectiveStatus(
                    reported: session.status,
                    attention: attentionSessions.contains(session.id) && session.id != activeId,
                    working: sid.map { workingSurfaces.contains($0) } ?? false
                ),
                tabColor: color
            )
        }

        if newTabs != tabs {
            tabs = newTabs
        }
    }

    // MARK: - Tab Actions

    /// Resolve a tab's session id to its current index in the controller's sessions.
    private func index(of tab: TabItem) -> Int? {
        controller?.sessions.firstIndex(where: { $0.id == tab.id })
    }

    func selectTab(_ tab: TabItem) {
        clearAttention(for: tab.id)
        guard let idx = index(of: tab) else { return }
        controller?.selectSession(at: idx)
    }

    func setTabColor(_ color: TerminalTabColor, for tab: TabItem) {
        guard let idx = index(of: tab) else { return }
        controller?.sessions[idx].tabColor = color
        refresh()
    }

    func closeTab(_ tab: TabItem) {
        guard let idx = index(of: tab) else { return }
        controller?.closeSession(at: idx)
    }

    func renameTab(_ tab: TabItem, to newTitle: String) {
        guard let idx = index(of: tab) else { return }
        controller?.sessions[idx].titleOverride = newTitle.isEmpty ? nil : newTitle
        refresh()
    }

    func promptRenameTab(_ tab: TabItem) {
        // TODO(Step 5 follow-up): prompt against the specific session, not just the active one. For now
        // this edits the active session's title (the common case — rename is usually for the current tab).
        controller?.promptTabTitle()
    }

    func closeOtherTabs(_ tab: TabItem) {
        guard let controller else { return }
        // Close every session except `tab`, from the highest index downward so earlier indices stay
        // valid as sessions are removed.
        let indicesToClose = controller.sessions.enumerated()
            .filter { $0.element.id != tab.id }
            .map { $0.offset }
            .sorted(by: >)
        for idx in indicesToClose {
            controller.closeSession(at: idx)
        }
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard let controller else { return }
        guard sourceIndex != destinationIndex,
              controller.sessions.indices.contains(sourceIndex),
              controller.sessions.indices.contains(destinationIndex) else { return }
        controller.moveSession(from: sourceIndex, to: destinationIndex)
        refresh()
    }

    func closeTabsToTheRight(of tab: TabItem) {
        guard let controller, let idx = index(of: tab) else { return }
        // Close from highest index downward so earlier indices stay valid as sessions are removed.
        let indicesToClose = Array(controller.sessions.indices.filter { $0 > idx }).sorted(by: >)
        for i in indicesToClose {
            controller.closeSession(at: i)
        }
    }
}
