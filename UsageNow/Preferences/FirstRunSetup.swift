import Foundation
import Observation

@Observable @MainActor
final class FirstRunSetup {
    private static let key = "setup.completed.v1"
    private let defaults: UserDefaults
    private(set) var needsSetup: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Read before ProviderPreferences registers knownProviders. An upgrade
        // must preserve choices and must never interrupt the existing runtime.
        let usedBefore = ["knownProviders", "enabledProviders", "refreshInterval", "telemetry.lastReportedVersion"]
            .contains { defaults.object(forKey: $0) != nil }
        needsSetup = defaults.object(forKey: Self.key) == nil && !usedBefore
        if usedBefore { defaults.set(true, forKey: Self.key) }
    }

    func complete() {
        defaults.set(true, forKey: Self.key)
        needsSetup = false
    }
}
