import Foundation
import Observation

/// Local display selections. Monitoring, credentials and notification rules
/// belong to accounts and never change when a person changes their view.
struct AccountSet: Codable, Equatable, Identifiable, Sendable {
    enum BuiltIn: String, Codable, Sendable { case work, personal }
    var id: String
    var name: String
    var builtIn: BuiltIn? = nil
    var sources: [SourceKey] = []
    var menuBarSource: SourceKey? = nil

    var title: String {
        switch builtIn {
        case .work: String(localized: "Work")
        case .personal: String(localized: "Personal")
        case nil: name
        }
    }
}

@Observable @MainActor
final class AccountSets {
    static let allID = "all"
    private static let storageKey = "accountSets.v1"
    private static let selectionKey = "accountSets.selection.v1"
    private let defaults: UserDefaults
    private(set) var sets: [AccountSet]
    var selectedID: String {
        didSet {
            if selectedID != Self.allID && !sets.contains(where: { $0.id == selectedID }) { selectedID = Self.allID }
            defaults.set(selectedID, forKey: Self.selectionKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([AccountSet].self, from: $0) }
        var seen = Set<String>()
        let loaded = (stored ?? [
            AccountSet(id: "work", name: "", builtIn: .work),
            AccountSet(id: "personal", name: "", builtIn: .personal),
        ]).filter { $0.id != Self.allID && !$0.id.isEmpty && seen.insert($0.id).inserted }.map { value in
            var value = value
            var sources = Set<SourceKey>()
            value.sources = value.sources.filter { sources.insert($0).inserted }
            if let source = value.menuBarSource, !value.sources.contains(source) { value.menuBarSource = nil }
            return value
        }
        sets = loaded
        let selection = defaults.string(forKey: Self.selectionKey) ?? Self.allID
        selectedID = loaded.contains { $0.id == selection } ? selection : Self.allID
    }

    var active: AccountSet? { sets.first { $0.id == selectedID } }
    var title: String { active?.title ?? String(localized: "All accounts") }

    func update(_ set: AccountSet) {
        guard let index = sets.firstIndex(where: { $0.id == set.id }) else { return }
        var value = set
        var seen = Set<SourceKey>()
        value.sources = value.sources.filter { seen.insert($0).inserted }
        if let key = value.menuBarSource, !value.sources.contains(key) { value.menuBarSource = nil }
        sets[index] = value
        save()
    }

    @discardableResult func create(name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              !sets.contains(where: { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        let set = AccountSet(id: UUID().uuidString, name: name)
        sets.append(set)
        save()
        return set.id
    }

    func remove(id: String) {
        sets.removeAll { $0.id == id }
        if selectedID == id { selectedID = Self.allID }
        save()
    }

    func setMembership(_ included: Bool, source: SourceKey, in id: String) {
        guard var set = sets.first(where: { $0.id == id }) else { return }
        if included { if !set.sources.contains(source) { set.sources.append(source) } }
        else { set.sources.removeAll { $0 == source } }
        update(set)
    }

    func move(_ source: SourceKey, by offset: Int, in id: String) {
        guard var set = sets.first(where: { $0.id == id }), let from = set.sources.firstIndex(of: source) else { return }
        let to = min(max(0, from + offset), set.sources.count - 1)
        set.sources.remove(at: from)
        set.sources.insert(source, at: to)
        update(set)
    }

    /// Called only for real account deletion, not source availability or a
    /// provider being temporarily disabled. Renaming keeps the same identity.
    func reconcile(accounts: [ProviderAccount]) {
        let valid = Set(ProviderCatalog.available.map { SourceKey(provider: $0.id) }
            + accounts.map { SourceKey(provider: $0.provider, account: $0.id) })
        for set in sets {
            var updated = set
            updated.sources.removeAll { !valid.contains($0) }
            if let source = updated.menuBarSource, !valid.contains(source) { updated.menuBarSource = nil }
            if updated != set { update(updated) }
        }
    }

    func displaying(_ states: [ProviderState], enabled: Set<ProviderID>) -> [ProviderState] {
        let enabled = states.filter { enabled.contains($0.provider) }
        guard let active else { return enabled }
        return active.sources.compactMap { source in enabled.first { $0.id == source } }
    }

    func menuBarChoice(fallback: MenuBarChoice, states: [ProviderState], enabled: Set<ProviderID>) -> MenuBarChoice {
        guard let active else { return fallback }
        let visible = displaying(states, enabled: enabled)
        if let source = active.menuBarSource, visible.contains(where: { $0.id == source }),
           let mode = MenuBarDisplayMode.allCases.first(where: { $0.requiredProvider == source.provider }) {
            return MenuBarChoice(mode: mode, account: source.account)
        }
        return MenuBarChoice(mode: .mostCriticalPercentage)
    }

    private func save() { defaults.set(try? JSONEncoder().encode(sets), forKey: Self.storageKey) }
}
