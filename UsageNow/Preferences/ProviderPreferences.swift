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

    /// Both supported providers start enabled.
    static let defaultEnabled: Set<ProviderID> = ProviderCatalog.availableIDs

    private(set) var enabledProviders: Set<ProviderID> {
        didSet {
            guard enabledProviders != oldValue else { return }
            defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.stringArray(forKey: Self.key) else {
            enabledProviders = Self.defaultEnabled
            return
        }
        // Ignore unknown or not-yet-implemented identifiers.
        enabledProviders = Set(stored.compactMap(ProviderID.init(rawValue:)).filter(\.isAvailable))
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

    func binding(for provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled(provider) ?? false },
            set: { [weak self] in self?.setEnabled($0, for: provider) }
        )
    }
}
