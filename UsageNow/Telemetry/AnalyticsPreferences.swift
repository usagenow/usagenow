import Foundation
import Observation

/// The user's analytics consent. Off by default.
///
/// Consent alone sends nothing: a build also needs an endpoint, from the
/// `USAGENOW_TELEMETRY_ENDPOINT` build setting. Released builds are shipped
/// without one, so they transmit nothing whatever this value is.
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
