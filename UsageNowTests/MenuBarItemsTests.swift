import Foundation
import Testing
@testable import UsageNow

@MainActor
struct MenuBarItemsTests {
    private let codex = SourceKey(provider: .codex)
    private let claude = SourceKey(provider: .claudeCode)
    private let now = TestDates.noon
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "MenuBarItems.\(UUID())")! }

    @Test func upgradePreservesTheOriginalIconAndDisplayChoice() {
        let saved = defaults()
        saved.set("claudePercentage", forKey: "menuBarDisplayMode")
        saved.set("work", forKey: "menuBarAccount")
        let preferences = AppPreferences(defaults: saved)
        #expect(preferences.menuBarItems.layout == .usageNow)
        #expect(preferences.menuBarItems.sources.isEmpty)
        #expect(preferences.menuBarChoice == MenuBarChoice(mode: .claudePercentage, account: "work"))
    }

    @Test func selectionsAndOrderSurviveRelaunchAndSwitchingModes() {
        let saved = defaults()
        let preferences = AppPreferences(defaults: saved)
        preferences.menuBarItems = .init(layout: .providers, sources: [codex, claude])
        preferences.menuBarItems.move(claude, by: -1)
        let reloaded = AppPreferences(defaults: saved)
        #expect(reloaded.menuBarItems.layout == .providers)
        #expect(reloaded.menuBarItems.sources == [claude, codex])
        reloaded.menuBarItems.layout = .usageNow
        #expect(AppPreferences(defaults: saved).menuBarItems.sources == [claude, codex])
    }

    @Test func corruptConfigurationKeepsAnAccessibleDefaultIcon() {
        let saved = defaults()
        saved.set(Data(#"{"layout":"unknown","sources":[]}"#.utf8), forKey: "menuBarItems.v1")
        #expect(AppPreferences(defaults: saved).menuBarItems == MenuBarItemsConfiguration())
    }

    @Test func selectionIsUniqueAndBoundedToFourAccounts() {
        var items = MenuBarItemsConfiguration(layout: .providers, sources: [codex, codex, claude])
        items.select(codex, included: true)
        items.select(SourceKey(provider: .cursor), included: true)
        items.select(SourceKey(provider: .copilot), included: true)
        items.select(SourceKey(provider: .windsurf), included: true)
        #expect(items.sources == [codex, claude, SourceKey(provider: .cursor), SourceKey(provider: .copilot)])
        items.select(claude, included: false)
        items.select(SourceKey(provider: .windsurf), included: true)
        #expect(items.sources.last?.provider == .windsurf)
        #expect(items.sources.count == 4)
    }

    @Test func accountDeletionNeverSilentlyReplacesItWithTheFirstAccount() {
        var account = ProviderAccount(id: "account-a", provider: .codex, name: "Work")
        let added = SourceKey(provider: .codex, account: account.id)
        let items = MenuBarItemsConfiguration(layout: .providers, sources: [added, claude])
        account.name = "Renamed"
        #expect(items.validated(against: [account]).sources == [added, claude])
        #expect(items.validated(against: []).sources == [claude])
        let state = AppState(providers: [], defaults: defaults(), widgetSnapshots: WidgetSnapshotWriter(store: nil))
        #expect(state.preferences.menuBarItems.layout == .usageNow)
    }

    @Test func disabledAndOtherSetAccountsDisappearWithoutLosingTheSavedSelection() {
        let items = MenuBarItemsConfiguration(layout: .providers, sources: [claude, codex])
        let states = [ProviderState(provider: .codex), ProviderState(provider: .claudeCode)]
        let work = AccountSet(id: "work", name: "", builtIn: .work, sources: [codex])
        #expect(items.visibleSources(in: states, enabled: [.codex, .claudeCode], set: work) == [codex])
        #expect(items.visibleSources(in: states, enabled: [.codex], set: nil) == [codex])
        #expect(items.visibleSources(in: states, enabled: [.codex, .claudeCode], set: nil) == [claude, codex])
        #expect(items.sources == [claude, codex])
    }

    @Test func emptySetsDisabledAndMissingToolsLeaveTheUsageNowFallback() {
        let items = MenuBarItemsConfiguration(layout: .providers, sources: [codex])
        let loading = [ProviderState(provider: .codex)]
        #expect(items.visibleSources(in: loading, enabled: [.codex], set: nil) == [codex])
        #expect(items.visibleSources(in: loading, enabled: [], set: nil).isEmpty)
        #expect(items.visibleSources(in: loading, enabled: [.codex], set: AccountSet(id: "empty", name: "Empty")).isEmpty)
        let missing = [ProviderState(provider: .codex, snapshot: .notInstalled(.codex, at: now))]
        #expect(items.visibleSources(in: missing, enabled: [.codex], set: nil).isEmpty)
        #expect(items.visibleSources(in: [], enabled: [.codex], set: nil).isEmpty)
    }

    @Test func separateAccountsOfTheSameProviderKeepTheirOwnValuesAndNames() {
        let account = AccountTag(id: "work", name: "Work")
        let first = Fixtures.snapshot(.codex, fiveHour: 15, weekly: 20, at: now)
        var added = Fixtures.snapshot(.codex, fiveHour: 80, weekly: 45, at: now)
        added.account = account
        let firstReading = ProviderMenuBarReading(state: ProviderState(provider: .codex, snapshot: first), at: now)
        let secondReading = ProviderMenuBarReading(state: ProviderState(provider: .codex, account: account, snapshot: added), at: now)
        #expect(firstReading.usage?.value == 20)
        #expect(secondReading.usage?.value == 80)
        #expect(firstReading.source != secondReading.source)
        #expect(secondReading.displayName == "Codex · Work")
        #expect(UsageAmountStyle.remaining.displayValue(secondReading.usage!) == 20)
        #expect(UsageAmountStyle.used.displayValue(secondReading.usage!) == 80)
    }

    @Test func currentWindowsRespectResetsAndScopedLimits() {
        var snapshot = Fixtures.snapshot(.claudeCode, fiveHour: 99, weekly: 25, at: now)
        snapshot.windows[0].resetsAt = now
        snapshot.windows.append(UsageWindow(kind: .weekly, scope: "Opus", usage: UsagePercentage(percent: 60), resetsAt: now.addingTimeInterval(3600)))
        let reading = ProviderMenuBarReading(state: ProviderState(provider: .claudeCode, snapshot: snapshot), at: now)
        #expect(reading.usage?.value == 60)
        #expect(reading.window?.scope == "Opus")
        #expect(reading.window?.kind == .weekly)
        #expect(ProviderMenuBarReading(state: ProviderState(provider: .claudeCode, snapshot: snapshot),
            at: now.addingTimeInterval(4 * 86_400)).usage == nil)
    }

    @Test func localTokensAndFutureReadingsNeverBecomeAQuotaPercentage() {
        var snapshot = Fixtures.snapshot(.gemini, at: now)
        snapshot.windows = []
        #expect(snapshot.activity.tokensToday != nil)
        #expect(ProviderMenuBarReading(state: ProviderState(provider: .gemini, snapshot: snapshot), at: now).usage == nil)
        let future = Fixtures.snapshot(.codex, at: now.addingTimeInterval(100))
        #expect(ProviderMenuBarReading(state: ProviderState(provider: .codex, snapshot: future), at: now).usage == nil)
    }

    @Test func expiredSignInAndRefreshFailureKeepAnHonestStaleMarker() {
        var snapshot = Fixtures.snapshot(.claudeCode, at: now)
        snapshot.limitsUpdatedAt = now.addingTimeInterval(-1800)
        let failed = ProviderState(provider: .claudeCode, snapshot: snapshot, failure: RefreshFailure(message: "Offline", date: now))
        let reading = ProviderMenuBarReading(state: failed, at: now)
        #expect(reading.isStale)
        #expect(reading.updatedAt == snapshot.limitsUpdatedAt)
        #expect(reading.usage != nil)
        snapshot.status = .notAuthenticated
        #expect(ProviderMenuBarReading(state: ProviderState(provider: .claudeCode, snapshot: snapshot), at: now).usage == nil)
    }

    @Test func clickingAnAccountFocusesItWithoutRevealingAccountsOutsideTheSet() {
        let first = ProviderState(provider: .codex)
        let added = ProviderState(provider: .codex, account: AccountTag(id: "work", name: "Work"))
        let states = [first, ProviderState(provider: .claudeCode), added]
        let focused = ProviderMenuBarReading.focusing(added.id, in: states)
        #expect(focused.first?.id == added.id)
        #expect(Set(focused.map(\.id)) == Set(states.map(\.id)))
        #expect(ProviderMenuBarReading.focusing(added.id, in: [first]) == [first])
    }
}
