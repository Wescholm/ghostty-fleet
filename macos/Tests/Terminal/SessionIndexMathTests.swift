import Testing
@testable import Ghostty

/// Pure index arithmetic behind the controller's session mutators (close/restore/move/restore-window).
/// The audit traced these as correct but untestable in place; this pins them as a regression guard.
@Suite
struct SessionIndexMathTests {
    @Test func clampedKeepsInRange() {
        #expect(SessionIndexMath.clamped(0, count: 3) == 0)
        #expect(SessionIndexMath.clamped(2, count: 3) == 2)
        #expect(SessionIndexMath.clamped(5, count: 3) == 2)   // past the end → last
        #expect(SessionIndexMath.clamped(-1, count: 3) == 0)  // negative → first
        #expect(SessionIndexMath.clamped(4, count: 0) == 0)   // empty → 0
    }

    @Test func neighborWhenClosing() {
        // Closing the last session goes to the previous; otherwise to the next.
        #expect(SessionIndexMath.neighborIndex(closing: 2, count: 3) == 1) // last → previous
        #expect(SessionIndexMath.neighborIndex(closing: 0, count: 3) == 1) // first → next
        #expect(SessionIndexMath.neighborIndex(closing: 1, count: 3) == 2) // middle → next
    }

    @Test func activeIndexAfterRemoval() {
        // Removing before the active shifts it down; removing at/after leaves it.
        #expect(SessionIndexMath.activeIndexAfterRemoval(active: 2, removed: 0) == 1)
        #expect(SessionIndexMath.activeIndexAfterRemoval(active: 2, removed: 1) == 1)
        #expect(SessionIndexMath.activeIndexAfterRemoval(active: 2, removed: 2) == 2) // removed == active
        #expect(SessionIndexMath.activeIndexAfterRemoval(active: 1, removed: 2) == 1) // removed after
        #expect(SessionIndexMath.activeIndexAfterRemoval(active: 0, removed: 0) == 0)
    }

    @Test func activeIndexAfterInsertion() {
        // Inserting at or before the active pushes it up; inserting after leaves it.
        #expect(SessionIndexMath.activeIndexAfterInsertion(active: 1, inserted: 0) == 2)
        #expect(SessionIndexMath.activeIndexAfterInsertion(active: 1, inserted: 1) == 2) // inserted == active
        #expect(SessionIndexMath.activeIndexAfterInsertion(active: 1, inserted: 2) == 1) // inserted after
        #expect(SessionIndexMath.activeIndexAfterInsertion(active: 0, inserted: 0) == 1)
    }

    /// End-to-end of the close path's two-step math: switch to the neighbor, then fix the active index
    /// after removing the closed session. Closing a non-active session must leave the active session's
    /// identity (here represented by its post-removal index) pointing at the same session.
    @Test func closeNonActiveKeepsActive() {
        // sessions [A,B,C], active = C (2), close A (0). Active C should end at index 1.
        let afterRemoval = SessionIndexMath.activeIndexAfterRemoval(active: 2, removed: 0)
        #expect(afterRemoval == 1)
    }
}
