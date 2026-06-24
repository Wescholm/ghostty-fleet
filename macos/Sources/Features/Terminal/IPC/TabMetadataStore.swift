import Foundation
import Cocoa

/// Stores per-tab metadata (status entries) that can be set via IPC.
///
/// Keyed by the in-app ``Session``'s UUID. (`ghosttyctl set-status` passes a per-surface `GHOSTTY_TAB_ID`;
/// `GhosttyIPCServer` resolves that surface to its owning session and stores under the *session* id, so
/// status follows the session across surface swaps/splits and shows for background sessions — G1. The
/// `tabId:` parameter name is kept for source stability.)
@MainActor
final class TabMetadataStore: ObservableObject {
    static let shared = TabMetadataStore()

    struct StatusEntry: Equatable, Codable {
        let key: String
        let value: String
        let icon: String?  // SF Symbol name, optional
    }

    /// Status entries keyed by tab UUID, then by status key
    @Published private(set) var entries: [UUID: [String: StatusEntry]] = [:]

    private init() {}

    func setStatus(tabId: UUID, key: String, value: String, icon: String? = nil) {
        if entries[tabId] == nil {
            entries[tabId] = [:]
        }
        entries[tabId]?[key] = StatusEntry(key: key, value: value, icon: icon)
    }

    func clearStatus(tabId: UUID, key: String) {
        entries[tabId]?.removeValue(forKey: key)
        if entries[tabId]?.isEmpty == true {
            entries.removeValue(forKey: tabId)
        }
    }

    func statusEntries(for tabId: UUID) -> [StatusEntry] {
        guard let tabEntries = entries[tabId] else { return [] }
        return tabEntries.values.sorted { $0.key < $1.key }
    }

    func removeAll(for tabId: UUID) {
        entries.removeValue(forKey: tabId)
    }
}
