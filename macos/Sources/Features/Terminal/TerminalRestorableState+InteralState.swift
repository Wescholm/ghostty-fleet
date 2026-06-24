import AppKit

extension TerminalRestorableState {
    /// One in-app ``Session``'s restorable state (sidebar re-architecture, Step 8): its split tree plus
    /// the per-session metadata the sidebar renders. The `Session`'s `id` is intentionally not stored —
    /// it's only meaningful within a single run, so restored sessions get fresh ids.
    struct SessionState<ViewType: NSView & Codable & Identifiable>: Codable {
        let surfaceTree: SplitTree<ViewType>
        let status: SessionStatus
        let titleOverride: String?
        let tabColor: TerminalTabColor?
    }

    /// Internal State we use to perform unit tests
    ///
    /// Since we can't really change the type of `TerminalRestorableState`
    /// due to `CodableBridge<TerminalRestorableState>` supporting secure coding,
    /// we use an internal type to perform migration and tests
    struct InternalState<ViewType: NSView & Codable & Identifiable>: Codable {
        // MARK: - Version 5 (1.2.3)
        let focusedSurface: String?
        let surfaceTree: SplitTree<ViewType>

        // MARK: - Version 7 (1.3.0)
        let effectiveFullscreenMode: FullscreenMode?
        let tabColor: TerminalTabColor?
        let titleOverride: String?

        // MARK: - Version 8 (sidebar fork: in-app sessions)
        // All in-app sessions of the window + which one is active. Optional so pre-v8 archives (no
        // `sessions` key) still decode — those restore via the legacy single-tree path
        // (`surfaceTree` above). When `sessions` is present it is the source of truth and the top-level
        // `surfaceTree` is empty, so the active session's surfaces aren't decoded twice.
        let sessions: [SessionState<ViewType>]?
        let activeSessionIndex: Int?
    }
}

extension TerminalRestorableState.InternalState where ViewType == Ghostty.SurfaceView {
    init(from controller: TerminalController) {
        let sessions = controller.sessions.map { session in
            TerminalRestorableState.SessionState<Ghostty.SurfaceView>(
                surfaceTree: session.surfaceTree,
                status: session.status,
                titleOverride: session.titleOverride,
                tabColor: session.tabColor
            )
        }
        self.init(
            focusedSurface: controller.focusedSurface?.id.uuidString,
            // v8: every session's tree (incl. the active one) lives in `sessions`; keep the top-level
            // tree empty so the active surfaces aren't serialized — and decoded — twice.
            surfaceTree: .init(),
            effectiveFullscreenMode: controller.fullscreenStyle?.fullscreenMode,
            tabColor: (controller.window as? TerminalWindow)?.tabColor,
            titleOverride: controller.titleOverride,
            sessions: sessions,
            activeSessionIndex: controller.activeSessionIndex
        )
    }
}
