import Testing
import AppKit
@testable import Ghostty

/// The `SessionStatus` raw values are a wire + disk contract: they cross the `ghosttyctl state` IPC
/// (`tab.set-state`) and are serialized into restorable state (`SessionState`). Pin them so a rename
/// can't silently break the CLI or invalidate saved windows.
@Suite
struct SessionStatusTests {
    @Test func rawValuesAreStable() {
        #expect(SessionStatus.idle.rawValue == "idle")
        #expect(SessionStatus.running.rawValue == "running")
        #expect(SessionStatus.waiting.rawValue == "waiting")
        #expect(SessionStatus.done.rawValue == "done")
        #expect(SessionStatus.attention.rawValue == "attention")
        #expect(SessionStatus.error.rawValue == "error")
    }

    @Test func allCasesIsComplete() {
        #expect(SessionStatus.allCases.count == 6)
        #expect(Set(SessionStatus.allCases.map(\.rawValue)) ==
                ["idle", "running", "waiting", "done", "attention", "error"])
    }

    @Test func decodesFromRawValue() {
        #expect(SessionStatus(rawValue: "waiting") == .waiting)
        #expect(SessionStatus(rawValue: "bogus") == nil)
    }
}

/// The sidebar status-dot precedence policy (`attention > error > waiting > running > done > idle`,
/// with the CPU "working" heuristic counting as running but yielding to agent-reported error/waiting).
@MainActor
@Suite
struct SidebarStatusTests {
    private func eff(_ reported: SessionStatus, attention: Bool = false, working: Bool = false) -> SessionStatus {
        SidebarTabManager.effectiveStatus(reported: reported, attention: attention, working: working)
    }

    @Test func attentionWinsOverEverything() {
        #expect(eff(.error, attention: true) == .attention)
        #expect(eff(.running, attention: true, working: true) == .attention)
        #expect(eff(.attention) == .attention) // reported attention also counts
    }

    @Test func errorBeatsWaitingRunningAndWorking() {
        #expect(eff(.error) == .error)
        #expect(eff(.error, working: true) == .error)
    }

    @Test func waitingBeatsRunningAndWorking() {
        #expect(eff(.waiting) == .waiting)
        #expect(eff(.waiting, working: true) == .waiting)
    }

    @Test func runningFromReportOrCPU() {
        #expect(eff(.running) == .running)
        #expect(eff(.idle, working: true) == .running)   // CPU heuristic
        #expect(eff(.done, working: true) == .running)   // CPU overrides a stale done
    }

    @Test func doneAndIdleWhenQuiet() {
        #expect(eff(.done) == .done)
        #expect(eff(.idle) == .idle)
    }
}
