import Foundation
import Testing
@testable import UsageNow

@MainActor
struct ProviderPreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "ProviderPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func bothSupportedProvidersAreEnabledByDefault() {
        let preferences = ProviderPreferences(defaults: makeDefaults())
        #expect(preferences.enabledProviders == [.codex, .claudeCode])
    }

    @Test func choicesPersist() {
        let defaults = makeDefaults()
        let preferences = ProviderPreferences(defaults: defaults)
        preferences.setEnabled(false, for: .codex)
        #expect(ProviderPreferences(defaults: defaults).enabledProviders == [.claudeCode])

        preferences.setEnabled(true, for: .codex)
        #expect(ProviderPreferences(defaults: defaults).enabledProviders == [.codex, .claudeCode])
    }

    @Test func turningEverythingOffPersists() {
        let defaults = makeDefaults()
        let preferences = ProviderPreferences(defaults: defaults)
        preferences.setEnabled(false, for: .codex)
        preferences.setEnabled(false, for: .claudeCode)
        #expect(ProviderPreferences(defaults: defaults).enabledProviders.isEmpty)
    }

    @Test func comingSoonProvidersCannotBeEnabled() {
        let preferences = ProviderPreferences(defaults: makeDefaults())
        for definition in ProviderCatalog.comingSoon {
            preferences.setEnabled(true, for: definition.id)
            #expect(!preferences.isEnabled(definition.id))
        }
    }

    @Test func storedRoadmapOrUnknownIdentifiersAreIgnored() {
        let defaults = makeDefaults()
        defaults.set(["codex", "gemini", "somethingElse"], forKey: "enabledProviders")
        #expect(ProviderPreferences(defaults: defaults).enabledProviders == [.codex])
    }
}

struct ProviderCatalogTests {
    @Test func onlyCodexAndClaudeAreAvailable() {
        #expect(ProviderCatalog.availableIDs == [.codex, .claudeCode])
        #expect(ProviderCatalog.comingSoon.map(\.id) == [.gemini, .grok, .deepseek, .glm, .qwen, .kimi, .metaAI])
    }

    @Test func geminiLeadsTheRoadmap() {
        #expect(ProviderCatalog.comingSoon.first?.displayName == "Gemini CLI")
    }

    @Test func everyProviderHasMetadata() {
        for id in ProviderID.allCases {
            let definition = ProviderCatalog.definition(for: id)
            #expect(definition.id == id)
            #expect(!definition.displayName.isEmpty)
            // Roadmap entries are labels only: no description implying a feature.
            #expect((definition.summary != nil) == (definition.availability == .available))
        }
    }

    @Test func displayNamesAreNotIdentifiers() {
        #expect(ProviderID.claudeCode.rawValue == "claudeCode")
        #expect(ProviderID.claudeCode.displayName == "Claude Code")
        #expect(ProviderID.metaAI.rawValue == "metaAI")
    }

    @Test func menuBarModesFollowEnabledProviders() {
        #expect(MenuBarDisplayMode.available(for: [.codex, .claudeCode]) == MenuBarDisplayMode.allCases)
        #expect(MenuBarDisplayMode.available(for: [.codex]) == [.iconOnly, .mostCriticalPercentage, .codexPercentage])
        #expect(MenuBarDisplayMode.available(for: [.claudeCode]) == [.iconOnly, .mostCriticalPercentage, .claudePercentage])
        #expect(MenuBarDisplayMode.available(for: []) == [.iconOnly, .mostCriticalPercentage])
    }
}

@MainActor
struct EnabledProviderStoreTests {
    private let now = Date(timeIntervalSince1970: 1_789_120_800)

    private func makeStore(enabled: Set<ProviderID>) -> (UsageStore, StubProvider, StubProvider) {
        let codex = StubProvider(.codex, .success(Fixtures.snapshot(.codex, fiveHour: 74, weekly: 52, at: now)))
        let claude = StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, fiveHour: 43, weekly: 88, at: now)))
        return (UsageStore(providers: [codex, claude], enabledProviders: enabled), codex, claude)
    }

    @Test func bothEnabled() async {
        let (store, codex, claude) = makeStore(enabled: [.codex, .claudeCode])
        await store.refresh()
        guard case .providers(let states) = store.content else {
            Issue.record("Expected providers, got \(store.content)")
            return
        }
        #expect(states.map(\.provider) == [.codex, .claudeCode])
        #expect(await codex.fetchCount == 1)
        #expect(await claude.fetchCount == 1)
    }

    @Test func onlyCodexEnabled() async {
        let (store, codex, claude) = makeStore(enabled: [.codex])
        await store.refresh()
        guard case .providers(let states) = store.content else {
            Issue.record("Expected providers")
            return
        }
        #expect(states.map(\.provider) == [.codex])
        #expect(await codex.fetchCount == 1)
        #expect(await claude.fetchCount == 0, "A disabled provider must not be refreshed")
    }

    @Test func onlyClaudeEnabled() async {
        let (store, codex, claude) = makeStore(enabled: [.claudeCode])
        await store.refresh()
        guard case .providers(let states) = store.content else {
            Issue.record("Expected providers")
            return
        }
        #expect(states.map(\.provider) == [.claudeCode])
        #expect(await codex.fetchCount == 0)
        #expect(await claude.fetchCount == 1)
    }

    @Test func allDisabled() async {
        let (store, codex, claude) = makeStore(enabled: [])
        await store.refresh()
        #expect(store.content == .noProvidersEnabled)
        #expect(await codex.fetchCount == 0)
        #expect(await claude.fetchCount == 0)
        #expect(store.snapshots.isEmpty)
    }

    @Test func explicitRefreshOfADisabledProviderDoesNothing() async {
        let (store, codex, _) = makeStore(enabled: [.claudeCode])
        await store.refresh(only: [.codex], trigger: .manual)
        #expect(await codex.fetchCount == 0)
    }

    @Test func disablingRemovesStateAndFailures() async {
        let codex = StubProvider(.codex, .failure(ProviderError.refreshFailed(reason: "Offline")))
        let claude = StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, at: now)))
        let store = UsageStore(providers: [codex, claude])
        await store.refresh()
        #expect(store.hasFailures)

        await store.setEnabledProviders([.claudeCode])
        #expect(!store.hasFailures, "A disabled provider must not show errors")
        guard case .providers(let states) = store.content else {
            Issue.record("Expected providers")
            return
        }
        #expect(states.map(\.provider) == [.claudeCode])
    }

    @Test func enablingRefreshesTheNewProvider() async {
        let (store, codex, claude) = makeStore(enabled: [.claudeCode])
        await store.refresh()
        #expect(await codex.fetchCount == 0)

        await store.setEnabledProviders([.codex, .claudeCode])
        #expect(await codex.fetchCount == 1)
        #expect(await claude.fetchCount == 1, "Already-enabled providers aren't refreshed again")
    }

    @Test func menuBarCalculationsIgnoreDisabledProviders() async {
        let (store, _, _) = makeStore(enabled: [.codex, .claudeCode])
        await store.refresh()
        // Claude's weekly window is the most used at 88%.
        #expect(MenuBarDisplayMode.mostCriticalPercentage.usage(in: store.snapshots)?.displayValue == 88)

        await store.setEnabledProviders([.codex])
        #expect(MenuBarDisplayMode.mostCriticalPercentage.usage(in: store.snapshots)?.displayValue == 74)
        #expect(MenuBarDisplayMode.claudePercentage.usage(in: store.snapshots) == nil)
    }

    @Test func disabledClaudeNeverReachesTheExperimentalLimitsClient() async throws {
        let credentials = StubCredentials(token: "fake-token")
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let limits = ClaudeUsageLimitsClient(credentials: credentials, transport: transport)
        let directory = try TemporaryDirectory()
        let environment = ClaudeCodeEnvironment(
            configDirectory: directory.url,
            globalConfigFile: directory.url.appending(path: ".claude.json"),
            configDirectoryExists: true,
            configDirectoryIsReadable: true,
            globalConfigExists: false,
            hasExecutable: true
        )
        let claude = ClaudeCodeProvider(
            discover: { environment },
            limitsClient: limits,
            limitsEnabled: FeatureSwitch(true),
            now: { TestDates.noon },
            calendar: TestDates.utc
        )
        let store = UsageStore(providers: [claude], enabledProviders: [.codex])

        await store.refresh(trigger: .manual)

        #expect(await credentials.reads == 0, "No keychain access for a disabled provider")
        #expect(await transport.requests.isEmpty, "No network access for a disabled provider")
    }
}
