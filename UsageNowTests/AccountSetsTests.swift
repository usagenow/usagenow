import Foundation
import Testing
@testable import UsageNow

@MainActor
struct AccountSetsTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "AccountSets.\(UUID())")! }
    private let codex = SourceKey(provider: .codex)
    private let claude = SourceKey(provider: .claudeCode)

    @Test func upgradesStartWithAllAndNoHiddenAccounts() {
        let saved = defaults()
        saved.set(["codex", "claudeCode"], forKey: "enabledProviders")
        let sets = AccountSets(defaults: saved)
        #expect(sets.selectedID == AccountSets.allID)
        #expect(sets.sets.count == 2)
        #expect(saved.stringArray(forKey: "enabledProviders") == ["codex", "claudeCode"])
    }

    @Test func membershipOrderAndActiveSetPersist() throws {
        let saved = defaults()
        let sets = AccountSets(defaults: saved)
        let id = try #require(sets.create(name: "Client A"))
        sets.setMembership(true, source: codex, in: id)
        sets.setMembership(true, source: claude, in: id)
        sets.setMembership(true, source: codex, in: id)
        sets.move(claude, by: -1, in: id)
        sets.selectedID = id
        #expect(AccountSets(defaults: saved).active?.sources == [claude, codex])
        #expect(sets.create(name: "client a") == nil)
    }

    @Test func renameKeepsMembershipAndDeletionDoesNotSelectAnotherAccount() {
        let sets = AccountSets(defaults: defaults())
        var account = ProviderAccount(id: "stable-uuid", provider: .codex, name: "Old")
        let source = SourceKey(provider: .codex, account: account.id)
        sets.setMembership(true, source: source, in: "work")
        sets.selectedID = "work"
        account.name = "Renamed"
        sets.reconcile(accounts: [account])
        #expect(sets.active?.sources == [source])
        sets.reconcile(accounts: [])
        #expect(sets.active?.sources.isEmpty == true)
        #expect(sets.displaying([ProviderState(provider: .codex)], enabled: [.codex]).isEmpty)
    }

    @Test func disabledSourcesRetainTheirSelectionAndReturnInTheSamePlace() {
        let sets = AccountSets(defaults: defaults())
        sets.setMembership(true, source: claude, in: "work")
        sets.setMembership(true, source: codex, in: "work")
        sets.selectedID = "work"
        let states = [ProviderState(provider: .codex), ProviderState(provider: .claudeCode)]
        #expect(sets.displaying(states, enabled: [.codex]).map(\.id) == [codex])
        #expect(sets.displaying(states, enabled: [.codex, .claudeCode]).map(\.id) == [claude, codex])
        #expect(sets.active?.sources == [claude, codex])
    }

    @Test func removedSetFallsBackToAllButAnEmptySetStaysEmpty() {
        let sets = AccountSets(defaults: defaults())
        sets.selectedID = "personal"
        #expect(sets.displaying([ProviderState(provider: .codex)], enabled: [.codex]).isEmpty)
        sets.remove(id: "personal")
        #expect(sets.selectedID == AccountSets.allID)
        #expect(sets.displaying([ProviderState(provider: .codex)], enabled: [.codex]).count == 1)
    }

    @Test func widgetsFollowTheSetWithoutRestrictingPersonalizedWidgetsOrCLI() {
        let now = TestDates.noon
        let states = [ProviderState(provider: .codex, snapshot: Fixtures.snapshot(.codex, at: now)),
                      ProviderState(provider: .claudeCode, snapshot: Fixtures.snapshot(.claudeCode, at: now))]
        var snapshot = WidgetSnapshotWriter.makeSnapshot(states: states, enabledProviders: [.codex, .claudeCode], generatedAt: now)
        let original = snapshot
        snapshot.followedSelectionIDs = ["claudeCode"]
        #expect(snapshot.providers.count == 2, "The full safe snapshot remains available")
        #expect(snapshot.selecting([]).providers.map(\.provider) == [.claudeCode])
        #expect(snapshot.selecting(["codex"]).providers.map(\.provider) == [.codex])
        #expect(snapshot.needsReload(comparedTo: original, at: now))
        snapshot.followedSelectionIDs = []
        #expect(snapshot.selecting([]).providers.isEmpty)
        #expect(snapshot.selecting(["codex"]).providers.count == 1)
    }

    @Test func perSetMenuBarChoiceCannotShowAHiddenAccount() {
        let sets = AccountSets(defaults: defaults())
        sets.setMembership(true, source: codex, in: "work")
        sets.selectedID = "work"
        let choice = sets.menuBarChoice(fallback: .init(mode: .claudePercentage), states: [ProviderState(provider: .codex)], enabled: [.codex])
        #expect(choice.mode == .mostCriticalPercentage)
    }
}
