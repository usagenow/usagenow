import Foundation
import Testing
@testable import UsageNow

/// Codex, Claude Code, and Gemini CLI together: menu bar, widget, and store.
struct ThreeProvidersTests {
    private let now = TestDates.noon

    private var gemini: ProviderSnapshot {
        ProviderSnapshot(
            provider: .gemini,
            status: .available,
            recentModel: "gemini-2.5-pro",
            activity: LocalActivity(tokensToday: 1_200_000, requestsToday: 24),
            modelActivity: [ModelActivity(modelID: "gemini-2.5-pro", totalTokens: 1_200_000, requests: 24)],
            updatedAt: now
        )
    }

    // MARK: Menu bar

    @Test func mostCriticalIgnoresProvidersWithoutLimits() {
        let snapshots = [
            Fixtures.snapshot(.codex, fiveHour: 40, weekly: 20, at: now),
            Fixtures.snapshot(.claudeCode, fiveHour: 70, weekly: 30, at: now),
            gemini,
        ]
        let critical = UsageSummary.mostCritical(in: snapshots)
        #expect(critical?.provider == .claudeCode)
        #expect(MenuBarDisplayMode.mostCriticalPercentage.usage(in: snapshots)?.displayValue == 70)
    }

    @Test func geminiModeFallsBackToTheIconWithoutLimits() {
        let snapshots = [Fixtures.snapshot(.codex, at: now), gemini]
        #expect(MenuBarDisplayMode.geminiPercentage.usage(in: snapshots) == nil)
        #expect(MenuBarDisplayMode.geminiPercentage.requiredProvider == .gemini)
    }

    @Test func geminiModeWouldShowLimitsIfTheyExisted() {
        let snapshots = [Fixtures.snapshot(.gemini, fiveHour: 55, weekly: 10, at: now)]
        #expect(MenuBarDisplayMode.geminiPercentage.usage(in: snapshots)?.displayValue == 55)
    }

    @Test func onlyGeminiEnabledMeansNoPercentage() {
        #expect(MenuBarDisplayMode.mostCriticalPercentage.usage(in: [gemini]) == nil)
    }

    // MARK: Widget

    @MainActor
    @Test func geminiReachesTheWidgetWithoutModelDetails() throws {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            states: [
                ProviderState(provider: .codex, snapshot: Fixtures.snapshot(.codex, at: now)),
                ProviderState(provider: .claudeCode, snapshot: Fixtures.snapshot(.claudeCode, at: now)),
                ProviderState(provider: .gemini, snapshot: gemini),
            ],
            enabledProviders: [.codex, .claudeCode, .gemini],
            generatedAt: now
        )
        #expect(snapshot.providers.map(\.provider) == [.codex, .claudeCode, .gemini])
        let widgetGemini = try #require(snapshot.providers.last)
        #expect(widgetGemini.windows.isEmpty)
        #expect(widgetGemini.tokensToday == 1_200_000)

        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!json.contains("modelActivity"))
        #expect(!json.contains("requests\":24,\"model"))
    }

    @MainActor
    @Test func disabledGeminiIsLeftOutOfTheWidget() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            states: [
                ProviderState(provider: .codex, snapshot: Fixtures.snapshot(.codex, at: now)),
                ProviderState(provider: .gemini, snapshot: gemini),
            ],
            enabledProviders: [.codex],
            generatedAt: now
        )
        #expect(snapshot.providers.map(\.provider) == [.codex])
    }

    @Test func everythingFitsInItsUsualOrder() {
        let snapshot = WidgetSnapshot(generatedAt: now, state: .providers([widget(.codex, used: 10), widget(.claudeCode, used: 90), widget(.gemini, used: nil)]))
        #expect(snapshot.providers(fitting: 3).map(\.provider) == [.codex, .claudeCode, .gemini])
    }

    @Test func whenRoomIsShortTheTightestProvidersWinAndKeepTheirOrder() {
        let snapshot = WidgetSnapshot(generatedAt: now, state: .providers([widget(.codex, used: 10), widget(.claudeCode, used: 90), widget(.gemini, used: nil)]))
        #expect(snapshot.providers(fitting: 2).map(\.provider) == [.codex, .claudeCode])

        let limitsOnlyOnGemini = WidgetSnapshot(generatedAt: now, state: .providers([widget(.codex, used: nil), widget(.claudeCode, used: nil), widget(.gemini, used: 5)]))
        #expect(limitsOnlyOnGemini.providers(fitting: 2).map(\.provider) == [.codex, .gemini])
    }

    @Test func widgetLayoutsHaveBoundedRows() {
        #expect(SmallUsageWidgetView.maxRows == 3)
        #expect(MediumUsageWidgetView.maxColumns == 2)
        #expect(MediumUsageWidgetView.maxRows == 4)
    }

    private func widget(_ provider: ProviderID, used: Double?) -> WidgetProviderSnapshot {
        WidgetProviderSnapshot(
            provider: provider,
            planName: nil,
            modelName: nil,
            windows: used.map { [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: $0), resetsAt: now.addingTimeInterval(3_600))] } ?? [],
            tokensToday: 1,
            requestsToday: 1
        )
    }

    // MARK: Store

    @MainActor
    @Test func aFailingGeminiRefreshDoesntHoldBackTheOthers() async throws {
        let codex = StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)))
        let claude = StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, at: now)))
        let failingGemini = StubProvider(.gemini, .failure(ProviderError.refreshFailed(reason: "offline")), delay: .milliseconds(200))
        let store = UsageStore(providers: [codex, claude, failingGemini])

        await store.refresh()

        #expect(store.states.first { $0.provider == .codex }?.snapshot?.status == .available)
        #expect(store.states.first { $0.provider == .claudeCode }?.snapshot?.status == .available)
        #expect(store.states.first { $0.provider == .gemini }?.failure != nil)
    }
}
