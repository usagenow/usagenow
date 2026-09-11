import Foundation
import Observation

/// The user's analytics consent. Off by default.
///
/// No telemetry is transmitted in this build regardless of this value.
@Observable
@MainActor
final class AnalyticsPreferences {
    private static let sharingKey = "analytics.shareAnonymousUsage"

    var isSharingEnabled: Bool {
        didSet { defaults.set(isSharingEnabled, forKey: Self.sharingKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSharingEnabled = defaults.bool(forKey: Self.sharingKey)
    }
}
