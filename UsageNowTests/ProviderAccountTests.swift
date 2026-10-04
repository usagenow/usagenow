import Foundation
import Testing

@testable import UsageNow

@MainActor
struct ProviderAccountTests {
    private let now = TestDates.noon
    private let work = ProviderAccount(id: "A1", provider: .codex, name: "Work", folder: "/tmp/codex-work")

    // MARK: Store

    @Test func anAccountFollowsItsProviderUnderItsOwnName() async throws {
        let store = UsageStore(
            providers: [
                StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now))),
                StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, at: now))),
                StubProvider(.codex, .success(Fixtures.snapshot(.codex, weekly: 90, at: now)), account: work),
            ],
            order: [.codex, .claudeCode]
        )

        await store.refresh()

        #expect(store.states.map(\.displayName) == ["Codex", "Codex · Work", "Claude Code"])
        let account = try #require(store.states.first { $0.account != nil })
        #expect(account.snapshot?.account == work.tag)
        #expect(account.snapshot?.window(.weekly)?.usage == UsagePercentage(percent: 90))
        #expect(store.states[0].snapshot?.account == nil)
    }

    @Test func anAddedAccountIsReadAloneAndARemovedOneDisappears() async {
        let codex = StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)))
        let store = UsageStore(providers: [codex], order: [.codex])
        await store.refresh()

        let account = StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)), account: work)
        await store.setAccounts([account])
        #expect(store.states.map(\.displayName) == ["Codex", "Codex · Work"])
        #expect(store.states[1].snapshot != nil)
        #expect(await codex.fetchCount == 1)
        #expect(await account.fetchCount == 1)

        await store.setAccounts([])
        #expect(store.states.map(\.displayName) == ["Codex"])
    }

    @Test func renamingAnAccountRenamesItsRow() async {
        let store = UsageStore(providers: [StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)), account: work)])
        await store.refresh()

        var renamed = work
        renamed.name = "Client"
        await store.setAccounts([StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)), account: renamed)])

        #expect(store.states.map(\.displayName) == ["Codex · Client"])
        #expect(store.states[0].snapshot?.account?.name == "Client")
    }

    @Test func turningAProviderOffClearsItsAccountsToo() async {
        let store = UsageStore(providers: [
            StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now))),
            StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)), account: work),
        ])
        await store.refresh()

        await store.setEnabledProviders([])

        #expect(store.states.allSatisfy { $0.snapshot == nil })
        #expect(store.states.map(\.displayName) == ["Codex", "Codex · Work"])
    }

    // MARK: Preferences

    @Test func accountsAreKeptAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "accounts-\(UUID())"))
        let preferences = ProviderPreferences(defaults: defaults)
        preferences.addAccount(work)
        preferences.addAccount(ProviderAccount(provider: .deepseek, name: "Team"))
        // Gemini has one account per Mac; there's nothing to add.
        preferences.addAccount(ProviderAccount(provider: .gemini, name: "Other"))

        let reloaded = ProviderPreferences(defaults: defaults)
        #expect(reloaded.accounts.map(\.name) == ["Work", "Team"])
        #expect(reloaded.accounts(for: .codex) == [work])

        reloaded.removeAccounts(of: .deepseek)
        #expect(ProviderPreferences(defaults: defaults).accounts == [work])
    }

    @Test func renamingKeepsTheAccountAndRefusesADuplicate() throws {
        let defaults = try #require(UserDefaults(suiteName: "rename-\(UUID())"))
        let preferences = ProviderPreferences(defaults: defaults)
        let personal = ProviderAccount(provider: .codex, name: "Personal", folder: "/tmp/codex-personal")
        preferences.addAccount(work)
        preferences.addAccount(personal)

        preferences.renameAccount(id: work.id, to: "  Client ")
        #expect(preferences.accounts(for: .codex).map(\.name) == ["Client", "Personal"])
        #expect(preferences.accounts(for: .codex).first?.folder == work.folder)

        preferences.renameAccount(id: work.id, to: "personal")
        preferences.renameAccount(id: work.id, to: "   ")
        #expect(ProviderPreferences(defaults: defaults).accounts(for: .codex).map(\.name) == ["Client", "Personal"])
    }

    // MARK: Keys

    @Test func anAddedAccountReadsItsOwnKey() async throws {
        let keys = MemoryKeyStore()
        let team = ProviderAccount(id: "B2", provider: .deepseek, name: "Team")
        try keys.setKey("sk-team", for: .deepseek, account: team.id)
        let transport = StubTransport(status: 200, body: #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"5.00"}]}"#)

        let first = try await APIKeyProvider.deepSeek(keys: keys, transport: transport).fetchSnapshot(trigger: .automatic)
        let added = try await APIKeyProvider.deepSeek(keys: keys, transport: transport).reading(team).fetchSnapshot(trigger: .automatic)

        #expect(first.status == .notInstalled)
        #expect(added.status == .available)
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-team")
        #expect(KeychainAPIKeyStore.item(.deepseek, nil) == "deepseek")
        #expect(KeychainAPIKeyStore.item(.deepseek, "B2") == "deepseek.B2")
    }

    // MARK: Notifications

    @Test func anAccountsLimitsAreRememberedApartAndNamed() {
        var snapshot = Fixtures.snapshot(.codex, fiveHour: 85, weekly: 10, at: now)
        snapshot.account = work.tag
        var memory = LimitNoticePlanner.Memory()

        let actions = LimitNoticePlanner.plan(snapshots: [Fixtures.snapshot(.codex, fiveHour: 85, weekly: 10, at: now), snapshot], memory: &memory, now: now)

        #expect(Set(memory.keys.compactMap { $0.split(separator: "|").first.map(String.init) }) == ["codex", "codex@A1"])
        let titles = actions.compactMap { action -> String? in
            if case .deliver(let notice) = action { return notice.title(style: .remaining) }
            return nil
        }
        #expect(titles.contains { $0.hasPrefix("Codex · Work:") })

        _ = LimitNoticePlanner.forget(providersOtherThan: [], memory: &memory)
        #expect(memory.isEmpty)
    }

    // MARK: Widget and report

    @Test func theWidgetShowsTheAccountsName() {
        var state = ProviderState(provider: .codex, account: work.tag)
        state.snapshot = Fixtures.snapshot(.codex, at: now)
        let main = ProviderState(provider: .codex, snapshot: Fixtures.snapshot(.codex, at: now))

        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [main, state], enabledProviders: [.codex], generatedAt: now)

        #expect(snapshot.providers.map(\.displayName) == ["Codex", "Codex · Work"])
        #expect(Set(snapshot.providers.map(\.id)).count == 2)
    }

    @Test func theReportNumbersAccountsInsteadOfNamingThem() {
        var account = ProviderState(provider: .codex, account: AccountTag(id: "A1", name: "Jane's Work"))
        account.snapshot = Fixtures.snapshot(.codex, at: now)
        let report = DiagnosticReport.make(
            states: [ProviderState(provider: .codex), account],
            order: [.codex],
            enabled: [.codex],
            hasAPIKey: { _ in false },
            settings: DiagnosticReport.Settings(
                appearance: "system", usageAmountStyle: "remaining", showsActivityHistory: true,
                refreshInterval: "300s", menuBarDisplayMode: "iconOnly", fetchClaudeUsageLimits: false
            ),
            now: now
        )

        #expect(report.contains("- Codex, added account 1: available"))
        #expect(!report.contains("Jane"))
    }
}

/// Keys in memory, the way the Keychain store names them.
final class MemoryKeyStore: APIKeyStoring, @unchecked Sendable {
    private var keys: [String: String] = [:]

    func key(for provider: ProviderID, account: String?) throws -> String? { keys[KeychainAPIKeyStore.item(provider, account)] }
    func setKey(_ key: String, for provider: ProviderID, account: String?) throws { keys[KeychainAPIKeyStore.item(provider, account)] = key }
    func removeKey(for provider: ProviderID, account: String?) throws { keys[KeychainAPIKeyStore.item(provider, account)] = nil }
}
