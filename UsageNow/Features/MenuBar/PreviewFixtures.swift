#if DEBUG
import Foundation

/// Ready-made stores for SwiftUI previews. No running app or backend required.
@MainActor
enum PreviewFixtures {
    static func snapshot(_ provider: ProviderID, _ scenario: MockScenario, now: Date = .now) -> ProviderSnapshot? {
        switch provider {
        case .codex: try? MockCodexProvider(scenario: scenario, referenceDate: now, now: { now }).snapshot()
        case .claudeCode: try? MockClaudeProvider(scenario: scenario, referenceDate: now, now: { now }).snapshot()
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
