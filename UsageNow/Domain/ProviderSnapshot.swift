import Foundation

/// A provider's normalized usage at a point in time.
///
/// This is the only shape of usage data the UI understands. Real providers
/// translate their tool-specific sources into it. Everything except the
/// provider and status is optional, because real sources may not offer it.
struct ProviderSnapshot: Sendable, Equatable, Identifiable {
    /// Data older than this is shown with an "Updated … ago" note.
    static let staleThreshold: TimeInterval = 10 * 60

    let provider: ProviderID
    var status: ProviderStatus
    /// Subscription plan label such as "Pro", only when a reliable source
    /// states it explicitly. Never inferred.
    var planName: String? = nil
    /// Most recently observed model identifier, e.g. "gpt-5.6-sol".
    var recentModel: String? = nil
    /// Quota windows actually reported by the provider — zero, one, or many.
    var windows: [UsageWindow] = []
    /// Set when quota is missing for a reason worth explaining.
    var quotaUnavailableReason: QuotaUnavailableReason? = nil
    var activity: LocalActivity = .unknown
    /// Today's activity per model, most active first. Independent of
    /// `windows`: account limits aren't split by model.
    var modelActivity: [ModelActivity] = []
    /// Money on a prepaid API account, for providers connected with the
    /// person's own API key. `nil` for subscription tools.
    var balance: AccountBalance? = nil
    /// When this snapshot was assembled.
    var updatedAt: Date
    /// When the quota windows were captured, if earlier than `updatedAt` —
    /// for example when they come from a cache or a fallback source.
    var limitsUpdatedAt: Date? = nil

    var id: ProviderID { provider }

    var capabilities: ProviderCapabilities {
        var capabilities: ProviderCapabilities = []
        if windows.contains(where: { $0.usage != nil }) { capabilities.insert(.quota) }
        if windows.contains(where: { $0.resetsAt != nil }) { capabilities.insert(.resetTimes) }
        if activity.tokensToday != nil { capabilities.insert(.tokenActivity) }
        if activity.requestsToday != nil { capabilities.insert(.requestActivity) }
        if recentModel != nil || !modelActivity.isEmpty { capabilities.insert(.modelActivity) }
        if planName != nil { capabilities.insert(.planInformation) }
        return capabilities
    }

    func window(_ kind: UsageWindowKind) -> UsageWindow? {
        windows.first { $0.kind == kind && $0.scope == nil } ?? windows.first { $0.kind == kind }
    }

    /// The window closest to exhaustion, ignoring windows with unknown usage.
    var mostCriticalWindow: UsageWindow? {
        guard status == .available else { return nil }
        return windows.mostRelevant
    }

    /// The date the displayed data is as fresh as: the quota capture time
    /// when quota is shown, otherwise the snapshot time.
    var dataDate: Date {
        windows.isEmpty ? updatedAt : (limitsUpdatedAt ?? updatedAt)
    }

    func isStale(at now: Date, threshold: TimeInterval = staleThreshold) -> Bool {
        now.timeIntervalSince(dataDate) > threshold
    }
}

/// An API account's money, exactly as the provider reports it.
///
/// Amounts stay in the currency the provider uses — a DeepSeek account in
/// yuan is shown in yuan — and are never converted or estimated.
struct AccountBalance: Sendable, Equatable {
    /// ISO 4217 code, e.g. "USD" or "CNY".
    var currency: String
    /// What's left to spend, when the provider reports it.
    var remaining: Decimal?
    var spentToday: Decimal? = nil
    var spentThisMonth: Decimal? = nil
    /// False when the provider says the balance can no longer pay for requests.
    var canMakeRequests = true
}

/// Which kinds of data a snapshot actually contains, so the UI can hide the rest.
struct ProviderCapabilities: OptionSet, Sendable, Hashable {
    let rawValue: Int

    static let quota = ProviderCapabilities(rawValue: 1 << 0)
    static let resetTimes = ProviderCapabilities(rawValue: 1 << 1)
    static let tokenActivity = ProviderCapabilities(rawValue: 1 << 2)
    static let requestActivity = ProviderCapabilities(rawValue: 1 << 3)
    static let modelActivity = ProviderCapabilities(rawValue: 1 << 4)
    static let planInformation = ProviderCapabilities(rawValue: 1 << 5)
}

extension ProviderSnapshot {
    static func notInstalled(_ provider: ProviderID, at date: Date) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, status: .notInstalled, updatedAt: date)
    }

    static func notAuthenticated(_ provider: ProviderID, at date: Date) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, status: .notAuthenticated, updatedAt: date)
    }

    static func unavailable(_ provider: ProviderID, at date: Date) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, status: .unavailable, updatedAt: date)
    }
}
