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

    @Test func everySupportedProviderIsEnabledByDefault() {
        let preferences = ProviderPreferences(defaults: makeDefaults())
        #expect(preferences.enabledProviders == [.codex, .claudeCode, .gemini, .antigravity, .kiro, .warp])
        // Providers read with an API key start off until a key is added.
        #expect(!preferences.isEnabled(.deepseek))
    }

    @Test func choicesPersist() {
        let defaults = makeDefaults()
        let preferences = ProviderPreferences(defaults: defaults)
        preferences.setEnabled(false, for: .codex)
        #expect(ProviderPreferences(defaults: defaults).enabledProviders == [.claudeCode, .gemini, .antigravity, .kiro, .warp])

        preferences.setEnabled(true, for: .codex)
        #expect(ProviderPreferences(defaults: defaults).enabledProviders == [.codex, .claudeCode, .gemini, .antigravity, .kiro, .warp])
    }

    @Test func turningEverythingOffPersists() {
        let defaults = makeDefaults()
        let preferences = ProviderPreferences(defaults: defaults)
        for provider in preferences.enabledProviders {
            preferences.setEnabled(false, for: provider)
        }
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
        defaults.set(["codex", "cursor", "somethingElse"], forKey: "enabledProviders")
        defaults.set(ProviderCatalog.availableIDs.map(\.rawValue), forKey: "knownProviders")
        #expect(ProviderPreferences(defaults: defaults).enabledProviders == [.codex])
    }

    @Test func aProviderAddedInAnUpdateStartsOnOnce() {
        // A 0.2.x user who turned Claude Code off; 0.2.x never recorded known providers.
        let defaults = makeDefaults()
        defaults.set(["codex"], forKey: "enabledProviders")

        let upgraded = ProviderPreferences(defaults: defaults)
        #expect(upgraded.enabledProviders == [.codex, .gemini, .antigravity, .kiro, .warp], "New providers start on; Claude Code stays off")

        upgraded.setEnabled(false, for: .gemini)
        #expect(ProviderPreferences(defaults: defaults).enabledProviders == [.codex, .antigravity, .kiro, .warp], "Turning it off sticks")
    }
}

@MainActor
struct ProviderOrderTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "ProviderOrderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultOrderIsTheCatalogs() {
        #expect(ProviderPreferences(defaults: makeDefaults()).order == [.codex, .claudeCode, .gemini, .antigravity, .kiro, .warp, .deepseek, .kimi, .openrouter])
    }

    @Test func draggingOntoAnotherTakesItsPlaceAndPersists() {
        let defaults = makeDefaults()
        let preferences = ProviderPreferences(defaults: defaults)
        preferences.move(.antigravity, to: .codex)
        #expect(preferences.order == [.antigravity, .codex, .claudeCode, .gemini, .kiro, .warp, .deepseek, .kimi, .openrouter])
        preferences.move(.codex, to: .gemini)
        #expect(preferences.order == [.antigravity, .claudeCode, .gemini, .codex, .kiro, .warp, .deepseek, .kimi, .openrouter])
        #expect(ProviderPreferences(defaults: defaults).order == [.antigravity, .claudeCode, .gemini, .codex, .kiro, .warp, .deepseek, .kimi, .openrouter])
    }

    @Test func moveUpAndDownStopAtTheEnds() {
        let preferences = ProviderPreferences(defaults: makeDefaults())
        preferences.move(.codex, by: -1)
        #expect(preferences.order.first == .codex)
        preferences.move(.codex, by: 1)
        #expect(preferences.order == [.claudeCode, .codex, .gemini, .antigravity, .kiro, .warp, .deepseek, .kimi, .openrouter])
        preferences.move(.antigravity, by: 50)
        #expect(preferences.order.last == .antigravity)
    }

    @Test func storedOrderDropsUnknownsAndAddsNewProvidersAtTheEnd() {
        #expect(ProviderPreferences.normalized([.gemini, .cursor, .gemini, .codex]) == [.gemini, .codex, .claudeCode, .antigravity, .kiro, .warp, .deepseek, .kimi, .openrouter])
    }

    @Test func storeFollowsTheOrder() async {
        let now = TestDates.noon
        let store = UsageStore(
            providers: [
                StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now))),
                StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, at: now))),
            ],
            enabledProviders: [.codex, .claudeCode],
            order: [.claudeCode, .codex]
        )
        await store.refresh()
        #expect(store.snapshots.map(\.provider) == [.claudeCode, .codex])

        store.setProviderOrder([.codex, .claudeCode])
        #expect(store.snapshots.map(\.provider) == [.codex, .claudeCode])
        let widget = WidgetSnapshotWriter.makeSnapshot(states: store.states, enabledProviders: [.codex, .claudeCode], generatedAt: now)
        #expect(widget.providers.map(\.provider) == [.codex, .claudeCode], "The widget follows the same order")
    }
}

struct ProviderCatalogTests {
    @Test func availableAndComingSoonProviders() {
        #expect(ProviderCatalog.availableIDs == [.codex, .claudeCode, .gemini, .antigravity, .kiro, .warp, .deepseek, .kimi, .openrouter])
        #expect(ProviderCatalog.comingSoon.map(\.id) == [.cursor, .copilot, .qwen])
        #expect(ProviderID.copilot.displayName == "GitHub Copilot")
    }

    @Test func geminiIsARealProvider() {
        #expect(ProviderID.gemini.isAvailable)
        #expect(ProviderID.gemini.rawValue == "gemini")
        #expect(ProviderID.gemini.displayName == "Gemini CLI")
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
        #expect(ProviderID.deepseek.rawValue == "deepseek")
    }

    @Test func menuBarModesFollowEnabledProviders() {
        #expect(MenuBarDisplayMode.available(for: [.codex, .claudeCode, .gemini, .antigravity, .kiro]) == MenuBarDisplayMode.allCases)
        #expect(MenuBarDisplayMode.available(for: [.kiro]) == [.iconOnly, .mostCriticalPercentage, .kiroPercentage])
        #expect(MenuBarDisplayMode.available(for: [.antigravity]) == [.iconOnly, .mostCriticalPercentage, .antigravityPercentage])
        #expect(MenuBarDisplayMode.available(for: [.gemini]) == [.iconOnly, .mostCriticalPercentage, .geminiPercentage])
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
            executable: URL(filePath: "/nonexistent/claude")
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
