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
    /// Whether limits read as left or used. Optional so a snapshot written
    /// before the choice existed still reads, as "left".
    var usageAmountStyle: UsageAmountStyle? = nil

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

    /// At most `limit` providers for a widget that can't fit them all.
    ///
    /// When everything fits, the order stays as configured so rows don't
    /// jump between refreshes. Otherwise providers closest to exhausting a
    /// limit win, then providers without limits, in their usual order.
    func providers(fitting limit: Int) -> [WidgetProviderSnapshot] {
        guard providers.count > limit else { return providers }
        let chosen = providers.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.mostRelevantWindow?.usage, rhs.element.mostRelevantWindow?.usage) {
                case let (left?, right?) where left != right: return left > right
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs.offset < rhs.offset
                }
            }
            .prefix(limit)
        return chosen.sorted { $0.offset < $1.offset }.map(\.element)
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
    /// Credits spent today, for tools that meter in credits (Kiro, Warp,
    /// Qoder). Optional, so snapshots from earlier versions still read.
    var creditsToday: Decimal? = nil
    /// Why quota is missing, when that's worth showing.
    var quotaUnavailableReason: QuotaUnavailableReason?
    /// The last days of activity, oldest first and today last, each as a
    /// share of the busiest of them (0–1) — the shape of the chart, not
    /// amounts. `nil` when the app's charts are turned off or there's no
    /// history; optional, so snapshots from earlier versions still read.
    var recentDays: [Double]? = nil

    var id: ProviderID { provider }

    /// Days shown in the widget's chart: two weeks fit its width.
    static let recentDayCount = 14

    /// Never localized; comes from the shared catalog.
    var displayName: String { provider.displayName }

    /// The window to show when there's only room for one.
    var mostRelevantWindow: UsageWindow? { windows.mostRelevant }

    /// Today's activity in the tool's own meter, for a provider with no
    /// limits to show: tokens where it records them, credits otherwise.
    /// "12.8M tokens today", or "12.8M tokens" when `short`.
    func activityText(short: Bool = false) -> String? {
        if let tokens = tokensToday {
            return short
                ? String(localized: "\(UsageFormatter.tokens(tokens)) tokens", comment: "Widget activity, e.g. 12.8M tokens")
                : String(localized: "\(UsageFormatter.tokens(tokens)) tokens today", comment: "Widget activity, e.g. 12.8M tokens today")
        }
        if let credits = creditsToday {
            return short
                ? String(localized: "\(UsageFormatter.credits(credits)) credits", comment: "Widget activity, e.g. 2.23 credits")
                : String(localized: "\(UsageFormatter.credits(credits)) credits today", comment: "Widget activity, e.g. 2.23 credits today")
        }
        return nil
    }
}

// MARK: Reading snapshots from another version

/// The app and its widget can briefly be different versions — during an
/// update, or with a development build running beside a release. A
/// snapshot from a newer app may name a provider, a kind of window, or a
/// reason this widget doesn't know. Those are left out, rather than failing
/// the whole snapshot and showing "Open UsageNow".
extension WidgetSnapshot.State {
    private enum CodingKeys: String, CodingKey {
        case providers, noProvidersEnabled, noProvidersDetected
    }

    private enum ProvidersKeys: String, CodingKey {
        case _0
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.providers) {
            let payload = try container.nestedContainer(keyedBy: ProvidersKeys.self, forKey: .providers)
            let providers = try payload.decode([Skippable<WidgetProviderSnapshot>].self, forKey: ._0)
            self = .providers(providers.compactMap(\.value))
        } else if container.contains(.noProvidersEnabled) {
            self = .noProvidersEnabled
        } else if container.contains(.noProvidersDetected) {
            self = .noProvidersDetected
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown widget state"))
        }
    }
}

extension WidgetProviderSnapshot {
    private enum CodingKeys: String, CodingKey {
        case provider, planName, modelName, windows, tokensToday, requestsToday, creditsToday, quotaUnavailableReason, recentDays
    }

    /// An unknown provider fails, so the list can skip it; an unknown window
    /// or reason is dropped, and the rest of the provider still shows.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ProviderID.self, forKey: .provider)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        windows = (try container.decodeIfPresent([Skippable<UsageWindow>].self, forKey: .windows) ?? []).compactMap(\.value)
        tokensToday = try container.decodeIfPresent(Int64.self, forKey: .tokensToday)
        requestsToday = try container.decodeIfPresent(Int64.self, forKey: .requestsToday)
        creditsToday = try container.decodeIfPresent(Decimal.self, forKey: .creditsToday)
        quotaUnavailableReason = try? container.decodeIfPresent(QuotaUnavailableReason.self, forKey: .quotaUnavailableReason)
        recentDays = try? container.decodeIfPresent([Double].self, forKey: .recentDays)
    }
}

/// Decodes a value, or nothing if this version can't read it.
private struct Skippable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
