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
    /// What was available before `knownProviders` was recorded (0.2.x).
    private static let initiallyKnown: Set<ProviderID> = [.codex, .claudeCode]

    /// Every supported provider starts enabled.
    static let defaultEnabled: Set<ProviderID> = ProviderCatalog.availableIDs

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

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        let added = ProviderCatalog.availableIDs.subtracting(known)
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
