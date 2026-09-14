import Foundation

/// Real Antigravity usage.
///
/// - Quota: only through the experimental `AntigravityQuotaClient`, when the
///   user turned it on. Antigravity's limits are shared by groups of models
///   and weekly, so each group becomes a scoped window.
/// - Activity: none. `agy` stores conversations in an undocumented binary
///   format, and UsageNow doesn't guess at token counts.
///
/// UsageNow never refreshes, modifies, or stores the Google sign-in `agy` saved.
struct AntigravityProvider: UsageProvider {
    let id: ProviderID = .antigravity

    private let discover: @Sendable () -> AntigravityEnvironment
    private let limitsClient: AntigravityQuotaClient?
    private let limitsEnabled: FeatureSwitch
    private let now: @Sendable () -> Date

    init(
        discover: @escaping @Sendable () -> AntigravityEnvironment = { .discover() },
        limitsClient: AntigravityQuotaClient? = nil,
        limitsEnabled: FeatureSwitch = FeatureSwitch(false),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.discover = discover
        self.limitsClient = limitsClient
        self.limitsEnabled = limitsEnabled
        self.now = now
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.antigravity, at: date) }
        guard environment.hasSavedSignIn else { return .notAuthenticated(.antigravity, at: date) }

        var limits: QuotaCache<[UsageWindow]>.Entry?
        var availability = QuotaSourceAvailability.disabled
        if let limitsClient, limitsEnabled.isOn {
            limits = await limitsClient.windows(trigger: trigger, now: now)
            availability = await limitsClient.availability
        }
        let windows = limits?.value.asOf(date) ?? []

        return ProviderSnapshot(
            provider: .antigravity,
            status: .available,
            windows: windows,
            quotaUnavailableReason: windows.contains { $0.usage != nil } ? nil : availability.unavailableReason,
            updatedAt: date,
            limitsUpdatedAt: windows.isEmpty ? nil : limits?.fetchedAt
        )
    }
}
