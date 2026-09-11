import Foundation

/// What the widget is allowed to know.
///
/// Only display values live here: provider identity, remaining quota,
/// reset dates, and local activity totals. Credentials, tokens, account
/// identifiers, file paths, project or session names, prompts, and raw
/// provider files must never reach this model — see the serialization
/// test that pins the JSON keys.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// Bumped when the shape changes. A widget that finds a newer version
    /// asks the user to open UsageNow instead of guessing.
    static let currentSchemaVersion = 1

    enum State: Codable, Sendable, Equatable {
        case providers([WidgetProviderSnapshot])
        /// Every provider is turned off in Settings.
        case noProvidersEnabled
        /// Providers are on, but none is installed on this Mac.
        case noProvidersDetected
    }

    var schemaVersion: Int = currentSchemaVersion
    /// When the main app produced this snapshot.
    var generatedAt: Date
    var state: State

    var providers: [WidgetProviderSnapshot] {
        if case .providers(let providers) = state { return providers }
        return []
    }

    /// The soonest upcoming reset across providers, for the small widget footer.
    func nextReset(after date: Date) -> (provider: ProviderID, resetsAt: Date)? {
        providers
            .compactMap { provider -> (ProviderID, Date)? in
                guard let next = provider.windows.compactMap(\.resetsAt).filter({ $0 > date }).min() else { return nil }
                return (provider.provider, next)
            }
            .min { $0.1 < $1.1 }
    }

    func isStale(at date: Date, threshold: TimeInterval = 10 * 60) -> Bool {
        date.timeIntervalSince(generatedAt) > threshold
    }
}

/// One provider's state, already filtered and sanitized by the main app.
struct WidgetProviderSnapshot: Codable, Sendable, Equatable, Identifiable {
    var provider: ProviderID
    /// Plan label the provider stated explicitly, e.g. "Pro".
    var planName: String?
    /// Display name of the most recently used model, e.g. "claude-opus-5".
    var modelName: String?
    /// Quota windows as reported — possibly none.
    var windows: [UsageWindow]
    /// Local activity totals for today.
    var tokensToday: Int64?
    var requestsToday: Int64?
    /// Why quota is missing, when that's worth showing.
    var quotaUnavailableReason: QuotaUnavailableReason?

    var id: ProviderID { provider }

    /// Never localized; comes from the shared catalog.
    var displayName: String { provider.displayName }

    /// The window to show when there's only room for one.
    var mostRelevantWindow: UsageWindow? { windows.mostRelevant }
}
