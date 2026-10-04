import Foundation
import Observation
import SwiftUI

/// Which providers UsageNow displays and refreshes.
///
/// Disabling a provider makes UsageNow behave as if it isn't there: no
/// refresh, no file or keychain access, no popover row, and no part in
/// menu bar calculations. It never touches the provider's own files,
/// credentials, or caches.
@Observable
@MainActor
final class ProviderPreferences {
    private static let key = "enabledProviders"
    /// Providers that were available when the choice was last saved, so a
    /// provider added in an update can be turned on once.
    private static let knownKey = "knownProviders"
    private static let orderKey = "providerOrder"
    private static let accountsKey = "providerAccounts"
    /// What was available before `knownProviders` was recorded (0.2.x).
    private static let initiallyKnown: Set<ProviderID> = [.codex, .claudeCode]

    /// Every supported provider that reads the tool on this Mac starts
    /// enabled, and stays out of sight until the tool is installed.
    ///
    /// Providers that need the person's own API key start off: they do
    /// nothing until a key is added, and turning one on is the moment to ask.
    static let defaultEnabled: Set<ProviderID> = Set(
        ProviderCatalog.available.filter { $0.apiKey == nil }.map(\.id)
    )

    private(set) var enabledProviders: Set<ProviderID> {
        didSet {
            guard enabledProviders != oldValue else { return }
            defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: Self.key)
        }
    }

    /// Every available provider, in the order the user arranged them. The
    /// popover and widget follow it; new providers join at the end.
    private(set) var order: [ProviderID] {
        didSet {
            guard order != oldValue else { return }
            defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        }
    }

    /// Accounts added beside the ones UsageNow finds itself, in the order
    /// they were added. Names and folders only; keys stay in the Keychain.
    private(set) var accounts: [ProviderAccount] {
        didSet {
            guard accounts != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.accountsKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accounts = defaults.data(forKey: Self.accountsKey)
            .flatMap { try? JSONDecoder().decode([ProviderAccount].self, from: $0) }?
            .filter { $0.provider.isAvailable && ProviderAccount.supportsAccounts($0.provider) } ?? []
        order = Self.normalized(defaults.stringArray(forKey: Self.orderKey)?.compactMap(ProviderID.init(rawValue:)) ?? [])
        defer { defaults.set(ProviderCatalog.availableIDs.map(\.rawValue).sorted(), forKey: Self.knownKey) }
        guard let stored = defaults.stringArray(forKey: Self.key) else {
            enabledProviders = Self.defaultEnabled
            return
        }
        // Ignore unknown or not-yet-implemented identifiers.
        let chosen = Set(stored.compactMap(ProviderID.init(rawValue:)).filter(\.isAvailable))
        // A provider that became available since the last launch starts on,
        // like it would for a new user; ones turned off stay off. It stays
        // out of sight until it's installed.
        let known = defaults.stringArray(forKey: Self.knownKey).map { Set($0.compactMap(ProviderID.init(rawValue:))) } ?? Self.initiallyKnown
        let added = Self.defaultEnabled.subtracting(known)
        enabledProviders = chosen.union(added)
        if !added.isEmpty {
            defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: Self.key)
        }
    }

    func isEnabled(_ provider: ProviderID) -> Bool {
        enabledProviders.contains(provider)
    }

    /// Roadmap providers can't be turned on.
    func setEnabled(_ isEnabled: Bool, for provider: ProviderID) {
        guard provider.isAvailable else { return }
        if isEnabled {
            enabledProviders.insert(provider)
        } else {
            enabledProviders.remove(provider)
        }
    }

    func accounts(for provider: ProviderID) -> [ProviderAccount] {
        accounts.filter { $0.provider == provider }
    }

    func addAccount(_ account: ProviderAccount) {
        guard ProviderAccount.supportsAccounts(account.provider), !accounts.contains(where: { $0.id == account.id }) else { return }
        accounts.append(account)
    }

    /// Renames an account. A blank name, or one another account of the same
    /// provider already has, is ignored.
    func renameAccount(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = accounts.firstIndex(where: { $0.id == id }), !trimmed.isEmpty else { return }
        let provider = accounts[index].provider
        let taken = accounts.contains {
            $0.id != id && $0.provider == provider && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        guard !taken else { return }
        accounts[index].name = trimmed
    }

    func removeAccount(id: String) {
        accounts.removeAll { $0.id == id }
    }

    func removeAccounts(of provider: ProviderID) {
        accounts.removeAll { $0.provider == provider }
    }

    /// Moves `provider` to where `target` is, shifting the rest.
    func move(_ provider: ProviderID, to target: ProviderID) {
        guard provider != target,
              let from = order.firstIndex(of: provider),
              let to = order.firstIndex(of: target) else { return }
        var reordered = order
        reordered.remove(at: from)
        reordered.insert(provider, at: to)
        order = reordered
    }

    /// Moves `provider` one place up (negative) or down (positive).
    func move(_ provider: ProviderID, by offset: Int) {
        guard let from = order.firstIndex(of: provider) else { return }
        let to = min(max(from + offset, 0), order.count - 1)
        guard to != from else { return }
        move(provider, to: order[to])
    }

    /// Stored order, minus providers that aren't available, plus any missing ones in catalog order.
    static func normalized(_ stored: [ProviderID]) -> [ProviderID] {
        var result: [ProviderID] = []
        for id in stored where id.isAvailable && !result.contains(id) { result.append(id) }
        for definition in ProviderCatalog.available where !result.contains(definition.id) { result.append(definition.id) }
        return result
    }

    func binding(for provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled(provider) ?? false },
            set: { [weak self] in self?.setEnabled($0, for: provider) }
        )
    }
}
