import Foundation

/// Decides which lifecycle events to report, and when.
///
/// Does nothing while analytics sharing is off: no events, no bookkeeping,
/// no identity. Turning sharing off deletes the installation identity.
/// It only ever learns which providers are installed — never their data.
@MainActor
final class TelemetryReporter {
    private enum Key {
        static let lastReportedVersion = "telemetry.lastReportedVersion"
        static let lastActiveDay = "telemetry.lastActiveDay"
        static let reportedProviders = "telemetry.reportedProviders"
    }

    private let client: any TelemetryClient
    private let preferences: AnalyticsPreferences
    private let identity: InstallationIdentity
    private let defaults: UserDefaults
    private let environment: TelemetryEnvironment
    private let now: () -> Date
    private let calendar: Calendar

    init(
        client: any TelemetryClient,
        preferences: AnalyticsPreferences,
        identity: InstallationIdentity,
        defaults: UserDefaults = .standard,
        environment: TelemetryEnvironment = .current,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.client = client
        self.preferences = preferences
        self.identity = identity
        self.defaults = defaults
        self.environment = environment
        self.now = now
        self.calendar = calendar
    }

    /// Call at launch and whenever the popover opens.
    func appDidBecomeActive() async {
        guard preferences.isSharingEnabled else { return }

        // Bookkeeping is written before awaiting so overlapping calls can't double-report.
        let version = "\(environment.appVersion) (\(environment.build))"
        let reportedVersion = defaults.string(forKey: Key.lastReportedVersion)
        defaults.set(version, forKey: Key.lastReportedVersion)
        switch reportedVersion {
        case nil: await client.send(.install)
        case let reported? where reported != version: await client.send(.appUpdated)
        default: break
        }

        let components = calendar.dateComponents([.year, .month, .day], from: now())
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        if defaults.string(forKey: Key.lastActiveDay) != day {
            defaults.set(day, forKey: Key.lastActiveDay)
            await client.send(.appActive)
        }
    }

    /// Reports each installed provider once per installation identity.
    func providersDetected(_ providers: Set<ProviderID>) async {
        guard preferences.isSharingEnabled else { return }
        var reported = Set(defaults.stringArray(forKey: Key.reportedProviders) ?? [])
        for provider in providers.sorted() where !reported.contains(provider.rawValue) {
            guard let event = TelemetryEvent.detected(provider) else { continue }
            reported.insert(provider.rawValue)
            defaults.set(Array(reported).sorted(), forKey: Key.reportedProviders)
            await client.send(event)
        }
    }

    /// Opting out deletes the identity and bookkeeping, so opting back in
    /// starts over as a new, unlinked installation.
    func sharingDidChange(detectedProviders: Set<ProviderID>) async {
        if preferences.isSharingEnabled {
            await appDidBecomeActive()
            await providersDetected(detectedProviders)
        } else {
            try? identity.reset()
            for key in [Key.lastReportedVersion, Key.lastActiveDay, Key.reportedProviders] {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
