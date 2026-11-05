import Foundation
import Testing
@testable import UsageNow

struct AdaptiveRefreshTests {
    private let now = TestDates.noon
    private func state(_ provider: ProviderID, age: TimeInterval) -> ProviderState {
        let date = now.addingTimeInterval(-age)
        return ProviderState(provider: provider, snapshot: Fixtures.snapshot(provider, at: date), lastAttemptAt: date)
    }

    @Test func accountsHaveIndependentDueTimesAndDisabledSourcesNeverRefresh() {
        let states = [state(.codex, age: 301), state(.claudeCode, age: 120)]
        var policy = AdaptiveRefreshPolicy()
        policy.observe(states, enabled: [.codex, .claudeCode])
        #expect(policy.dueSources(states, enabled: [.codex, .claudeCode], at: now, conditions: .init()) == [SourceKey(provider: .codex)])
        #expect(policy.dueSources(states, enabled: [.claudeCode], at: now, conditions: .init()).isEmpty)
    }

    @Test func lockPowerAndOfflineReduceRequests() {
        let states = [state(.codex, age: 600)]
        var policy = AdaptiveRefreshPolicy()
        policy.observe(states, enabled: [.codex])
        #expect(policy.dueSources(states, enabled: [.codex], at: now, conditions: .init(online: false)).isEmpty)
        #expect(policy.dueSources(states, enabled: [.codex], at: now, conditions: .init(screenLocked: true)).isEmpty)
        #expect(policy.dueSources(states, enabled: [.codex], at: now, conditions: .init(lowPower: true)).isEmpty)
        #expect(policy.dueSources(states, enabled: [.codex], at: now, conditions: .init(), afterWake: true).count == 1)
    }

    @Test func serverCooldownAndFailureBackoffSurviveWake() {
        var item = state(.codex, age: 301)
        item.failure = .init(message: "limited", date: item.lastAttemptAt!, retryAt: now.addingTimeInterval(3600))
        var policy = AdaptiveRefreshPolicy()
        policy.observe([item], enabled: [.codex])
        #expect(policy.dueSources([item], enabled: [.codex], at: now, conditions: .init(), afterWake: true).isEmpty)
        item.failure?.retryAt = nil
        #expect(policy.dueSources([item], enabled: [.codex], at: now, conditions: .init()).isEmpty)
        #expect(policy.dueSources([item], enabled: [.codex], at: now.addingTimeInterval(301), conditions: .init()).count == 1)
    }

    @Test func unchangedReadingsSlowDownButObservingACachedResultDoesNotCountAgain() {
        var policy = AdaptiveRefreshPolicy()
        var item = state(.codex, age: 1500)
        for offset in 0..<4 {
            let date = now.addingTimeInterval(Double(offset - 4) * 300)
            item.lastAttemptAt = date
            item.snapshot?.updatedAt = date
            policy.observe([item], enabled: [.codex])
        }
        #expect(policy.records[item.id]?.unchanged == 3)
        policy.observe([item], enabled: [.codex])
        #expect(policy.records[item.id]?.unchanged == 3)
        #expect(policy.dueSources([item], enabled: [.codex], at: now, conditions: .init()).isEmpty)
        item.snapshot?.activity.tokensToday = 42
        item.lastAttemptAt = now.addingTimeInterval(-301)
        policy.observe([item], enabled: [.codex])
        #expect(policy.dueSources([item], enabled: [.codex], at: now, conditions: .init()).count == 1)
    }

    @Test @MainActor func upgradeKeepsExistingRefreshChoiceAndNewInstallsUseAdaptive() {
        let defaults = UserDefaults(suiteName: "Adaptive.\(UUID())")!
        #expect(AppPreferences(defaults: defaults).refreshInterval == .adaptive)
        defaults.removeObject(forKey: "refreshInterval")
        defaults.set(["codex"], forKey: "knownProviders")
        #expect(AppPreferences(defaults: defaults).refreshInterval == .fiveMinutes)
        defaults.set(1800, forKey: "refreshInterval")
        #expect(AppPreferences(defaults: defaults).refreshInterval == .thirtyMinutes)
    }

    @Test @MainActor func adaptiveDefaultSurvivesSetupAndRelaunchWithoutSkippingSetup() {
        let defaults = UserDefaults(suiteName: "AdaptiveSetup.\(UUID())")!
        let setup = FirstRunSetup(defaults: defaults)
        let preferences = AppPreferences(defaults: defaults)
        #expect(setup.needsSetup)
        #expect(preferences.refreshInterval == .adaptive)
        _ = ProviderPreferences(defaults: defaults)
        setup.complete()
        #expect(AppPreferences(defaults: defaults).refreshInterval == .adaptive)
        #expect(!FirstRunSetup(defaults: defaults).needsSetup)
    }
}
