import Testing
import AppKit
@testable import Ghostty

/// Per-session status entries set via `ghosttyctl set-status` (keyed by `Session.id`). Each test uses a
/// fresh UUID and cleans up so the shared singleton doesn't bleed between tests.
@MainActor
@Suite
struct TabMetadataStoreTests {
    private let store = TabMetadataStore.shared

    @Test func setThenRead() {
        let id = UUID(); defer { store.removeAll(for: id) }
        store.setStatus(tabId: id, key: "agent", value: "running", icon: "hammer.fill")
        let entries = store.statusEntries(for: id)
        #expect(entries.count == 1)
        #expect(entries.first?.key == "agent")
        #expect(entries.first?.value == "running")
        #expect(entries.first?.icon == "hammer.fill")
    }

    @Test func multipleKeysAreSortedByKey() {
        let id = UUID(); defer { store.removeAll(for: id) }
        store.setStatus(tabId: id, key: "zeta", value: "1")
        store.setStatus(tabId: id, key: "alpha", value: "2")
        #expect(store.statusEntries(for: id).map(\.key) == ["alpha", "zeta"])
    }

    @Test func overwriteSameKey() {
        let id = UUID(); defer { store.removeAll(for: id) }
        store.setStatus(tabId: id, key: "k", value: "old")
        store.setStatus(tabId: id, key: "k", value: "new")
        #expect(store.statusEntries(for: id).count == 1)
        #expect(store.statusEntries(for: id).first?.value == "new")
    }

    @Test func clearKeyAndAutoPruneEmptyTab() {
        let id = UUID(); defer { store.removeAll(for: id) }
        store.setStatus(tabId: id, key: "a", value: "1")
        store.setStatus(tabId: id, key: "b", value: "2")
        store.clearStatus(tabId: id, key: "a")
        #expect(store.statusEntries(for: id).map(\.key) == ["b"])
        store.clearStatus(tabId: id, key: "b")
        #expect(store.statusEntries(for: id).isEmpty)
        #expect(store.entries[id] == nil) // last key cleared ⇒ tab entry pruned
    }

    @Test func unknownTabIsEmpty() {
        #expect(store.statusEntries(for: UUID()).isEmpty)
    }
}
