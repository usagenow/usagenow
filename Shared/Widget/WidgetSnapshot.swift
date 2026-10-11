import Foundation

/// What the widget is allowed to know.
///
/// Only display values live here: provider identity, remaining quota,
/// reset dates, and local activity totals. Credentials, tokens, account
/// identifiers, file paths, project or session names, prompts, and raw
/// provider files must never reach this model — see the serialization
/// test that pins the JSON keys.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    static let widgetKind = "UsageNowWidget"
    static let staleThreshold: TimeInterval = 10 * 60
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
    /// The language chosen in UsageNow, e.g. "ru"; `nil` follows macOS.
    /// The widget is its own process and doesn't share the app's setting.
    var language: String? = nil

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

    func isStale(at date: Date, threshold: TimeInterval = staleThreshold) -> Bool {
        date.timeIntervalSince(generatedAt) > threshold
    }

    /// A timeline can outlive the app that supplied it. A past reset is
    /// no longer evidence of the usage in the new window.
    func asOf(_ date: Date) -> WidgetSnapshot {
        guard case .providers(let providers) = state else { return self }
        var copy = self
        copy.state = .providers(providers.map { provider in
            var provider = provider
            provider.windows = provider.windows.asOf(date)
            return provider
        })
        return copy
    }

    /// Timestamp-only changes are written for the next timeline read, but
    /// don't spend another reload unless data became fresh or stale.
    func needsReload(comparedTo previous: WidgetSnapshot, at date: Date) -> Bool {
        var current = self
        var previous = previous
        current.generatedAt = previous.generatedAt
        if case .providers(let providers) = current.state,
           case .providers(let oldProviders) = previous.state {
            guard providers.map(\.id) == oldProviders.map(\.id) else { return true }
            for (provider, old) in zip(providers, oldProviders) {
                if provider.isStale(at: date) != old.isStale(at: date) { return true }
            }
            current.state = .providers(providers.map { var value = $0; value.updatedAt = nil; return value })
            previous.state = .providers(oldProviders.map { var value = $0; value.updatedAt = nil; return value })
        }
        return current != previous
    }
}

/// One provider's state, already filtered and sanitized by the main app.
struct WidgetProviderSnapshot: Codable, Sendable, Equatable, Identifiable {
    var provider: ProviderID
    /// The name the person gave an added account, e.g. "Work"; `nil` for
    /// the provider's own. Optional, so snapshots from earlier versions
    /// still read.
    var accountName: String? = nil
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
    /// When these displayed values were obtained, not when another
    /// provider caused the app to write the file. Optional for old readers.
    var updatedAt: Date? = nil
    /// Account counters, never confused with today's local activity.
    var totals: [UsageTotal]? = nil

    func isStale(at date: Date) -> Bool {
        guard let updatedAt else { return false }
        return date.timeIntervalSince(updatedAt) > WidgetSnapshot.staleThreshold
    }

    /// Account names are unique per provider, so this tells rows apart.
    var id: String { accountName.map { "\(provider.rawValue) · \($0)" } ?? provider.rawValue }

    /// Days shown in the widget's chart: two weeks fit its width.
    static let recentDayCount = 14

    /// "Codex", or "Codex · Work" for an added account. Never localized.
    var displayName: String { accountName.map { "\(provider.displayName) · \($0)" } ?? provider.displayName }

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
        if let total = totals?.first {
            return "\(String(localized: total.kind.title)): \(UsageFormatter.credits(total.value))"
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
        case provider, accountName, planName, modelName, windows, tokensToday, requestsToday, creditsToday, quotaUnavailableReason, recentDays, updatedAt, totals
    }

    /// An unknown provider fails, so the list can skip it; an unknown window
    /// or reason is dropped, and the rest of the provider still shows.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ProviderID.self, forKey: .provider)
        accountName = try? container.decodeIfPresent(String.self, forKey: .accountName)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        windows = (try container.decodeIfPresent([Skippable<UsageWindow>].self, forKey: .windows) ?? []).compactMap(\.value)
        tokensToday = try container.decodeIfPresent(Int64.self, forKey: .tokensToday)
        requestsToday = try container.decodeIfPresent(Int64.self, forKey: .requestsToday)
        creditsToday = try container.decodeIfPresent(Decimal.self, forKey: .creditsToday)
        quotaUnavailableReason = try? container.decodeIfPresent(QuotaUnavailableReason.self, forKey: .quotaUnavailableReason)
        recentDays = try? container.decodeIfPresent([Double].self, forKey: .recentDays)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        totals = (try? container.decodeIfPresent([Skippable<UsageTotal>].self, forKey: .totals))?.compactMap(\.value)
    }
}

/// Decodes a value, or nothing if this version can't read it.
private struct Skippable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
