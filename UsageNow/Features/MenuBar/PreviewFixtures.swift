#if DEBUG
import Foundation

/// Ready-made stores for SwiftUI previews. No running app or backend required.
@MainActor
enum PreviewFixtures {
    static func snapshot(_ provider: ProviderID, _ scenario: MockScenario, now: Date = .now) -> ProviderSnapshot? {
        switch provider {
        case .codex: try? MockCodexProvider(scenario: scenario, referenceDate: now, now: { now }).snapshot()
        case .claudeCode: try? MockClaudeProvider(scenario: scenario, referenceDate: now, now: { now }).snapshot()
        default: nil // Roadmap providers have no data.
        }
    }

    static func store(codex: MockScenario, claude: MockScenario) -> UsageStore {
        let now = Date.now
        return UsageStore(
            providers: [],
            states: [
                ProviderState(provider: .codex, snapshot: snapshot(.codex, codex, now: now)),
                ProviderState(provider: .claudeCode, snapshot: snapshot(.claudeCode, claude, now: now)),
            ],
            hasCompletedInitialLoad: true,
            lastRefreshAt: now
        )
    }

    /// Codex reports only a weekly window; Claude Code has no quota, just local activity.
    static func weeklyOnlyStore() -> UsageStore {
        let now = Date.now
        var codex = snapshot(.codex, .normal, now: now)
        codex?.windows.removeAll { $0.kind == .fiveHour }
        codex?.planName = "Plus"
        return UsageStore(
            providers: [],
            states: [
                ProviderState(provider: .codex, snapshot: codex),
                ProviderState(provider: .claudeCode, snapshot: snapshot(.claudeCode, .unavailable, now: now)),
            ],
            hasCompletedInitialLoad: true,
            lastRefreshAt: now
        )
    }

    /// A month of activity in the given metric.
    static func history(_ metric: ActivityHistory.Metric) -> ActivityHistory {
        let now = Date.now
        let factory = MockSnapshotFactory(
            profile: MockProfile(provider: .claudeCode, model: "claude-opus-5", firstFiveHourReset: 3600, weeklyReset: DateComponents(weekday: 2)),
            referenceDate: now,
            calendar: .current
        )
        var history = factory.history(tokensToday: 74_800_000, requestsToday: 312, now: now)
        guard metric != .tokens else { return history }
        history.metric = metric
        history.estimatedCost = nil
        history.topModel = nil
        for index in history.days.indices {
            history.days[index].estimatedCost = nil
            history.days[index].credits = metric == .credits ? Decimal(history.days[index].requests) / 8 : nil
        }
        history.credits = metric == .credits ? history.days.compactMap(\.credits).reduce(0, +) : nil
        return history
    }

    /// Every provider turned off in Settings.
    static func noProvidersEnabledStore() -> UsageStore {
        UsageStore(providers: [], enabledProviders: [], hasCompletedInitialLoad: true, lastRefreshAt: .now)
    }

    static func loadingStore() -> UsageStore {
        UsageStore(providers: [])
    }

    /// Codex failed to refresh and keeps showing data from 18 minutes ago.
    static func errorStore() -> UsageStore {
        let now = Date.now
        let old = now.addingTimeInterval(-18 * 60)
        let failure = RefreshFailure(message: "The mock Codex provider is set to fail.", date: now)
        return UsageStore(
            providers: [],
            states: [
                ProviderState(provider: .codex, snapshot: snapshot(.codex, .normal, now: old), failure: failure),
                ProviderState(provider: .claudeCode, snapshot: snapshot(.claudeCode, .normal, now: now)),
            ],
            hasCompletedInitialLoad: true,
            lastRefreshAt: now
        )
    }
}
#endif
