import Foundation
import Observation

/// The lifecycle / agent status of a ``Session``, surfaced as the sidebar card indicator.
///
/// Fed by layered signals (authoritative source wins; heuristics fall back) — see the "Session status
/// model" section of `SIDEBAR-REARCHITECTURE.md`:
/// - `.running` / `.waiting` / `.done` are authoritatively reported by the agent itself over the
///   `ghosttyctl` IPC (e.g. Claude Code hooks → `tab.set-status`).
/// - `.running` / `.idle` also derive from the foreground-process CPU poll and OSC 133 prompt marks.
/// - `.attention` comes from a bell / notification.
/// - `.error` comes from a non-zero command exit (OSC 133).
enum SessionStatus: String, Codable, CaseIterable {
    /// Shell at the prompt, nothing running.
    case idle

    /// A command / agent is actively working (foreground process busy, or an OSC 133 command running).
    case running

    /// Blocked on the user — e.g. an agent asking a question or awaiting approval. Agent-reported.
    case waiting

    /// Finished its work (e.g. an agent's Stop hook fired).
    case done

    /// Needs attention — a bell or notification fired (the orange dot today).
    case attention

    /// The last command failed (non-zero exit, via OSC 133).
    case error
}

/// A single in-window terminal **session**: one split tree plus the metadata the sidebar renders.
///
/// Part of the sidebar re-architecture (`SIDEBAR-REARCHITECTURE.md`). The plan is for one
/// `TerminalController` to own an ordered `[Session]` and switch the *active* one — replacing native
/// `NSWindow` tabbing, which is the root of the macOS-26 tab-bar bug class. This type is introduced
/// **additively in Step 1**: it is not yet referenced by the controller or the sidebar (that is
/// Steps 2+), so defining it changes no behavior.
///
/// It is a reference type so a session has a stable identity shared by the controller, the sidebar,
/// and the live-surface store. It uses the Observation framework's `@Observable` (the app's baseline
/// is now macOS 26): AppKit automatically observes the property accesses and invalidates/redraws the
/// views that read them, which is exactly what the upcoming surface-swap content host wants.
@Observable
final class Session: Identifiable {
    /// Stable identity for sidebar selection and the live-surface store. Survives reorder/rename and
    /// outlives any individual `SurfaceView`.
    let id: UUID

    /// This session's split layout (a single terminal, or splits). This is the unit the content host
    /// will mount when the session is active and keep alive (occluded) when it is not.
    var surfaceTree: SplitTree<Ghostty.SurfaceView>

    /// Lifecycle / agent status surfaced as the sidebar card indicator. See ``SessionStatus``.
    var status: SessionStatus

    /// User-set title override (from the rename action or `ghosttyctl rename`). When `nil` the card
    /// falls back to the live terminal title.
    var titleOverride: String?

    /// Optional accent color (sidebar "Tab Color" context menu / IPC).
    var tabColor: TerminalTabColor?

    init(
        id: UUID = UUID(),
        surfaceTree: SplitTree<Ghostty.SurfaceView> = .init(),
        status: SessionStatus = .idle,
        titleOverride: String? = nil,
        tabColor: TerminalTabColor? = nil
    ) {
        self.id = id
        self.surfaceTree = surfaceTree
        self.status = status
        self.titleOverride = titleOverride
        self.tabColor = tabColor
    }
}
