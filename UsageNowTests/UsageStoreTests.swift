import Foundation
import Testing
@testable import UsageNow

@MainActor
struct UsageStoreTests {
    private let now = Date(timeIntervalSince1970: 1_789_120_800)

    @Test func startsInLoadingState() {
        let store = UsageStore(providers: [StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)))])
        #expect(store.content == .loading)
        #expect(store.lastRefreshAt == nil)
    }

    @Test func refreshLoadsAllProviders() async {
        let store = UsageStore(providers: [
            StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now))),
            StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, at: now))),
        ], now: { [now] in now })

        await store.refresh()

        guard case .providers(let states) = store.content else {
            Issue.record("Expected providers, got \(store.content)")
            return
        }
        #expect(states.map(\.provider) == [.codex, .claudeCode])
        #expect(store.hasCompletedInitialLoad)
        #expect(!store.isRefreshing)
        #expect(store.lastRefreshAt == now)
    }

    @Test func notInstalledProvidersAreHidden() async {
        let store = UsageStore(providers: [
            StubProvider(.codex, .success(.notInstalled(.codex, at: now))),
            StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, at: now))),
        ])

        await store.refresh()

        guard case .providers(let states) = store.content else {
            Issue.record("Expected providers")
            return
        }
        #expect(states.map(\.provider) == [.claudeCode])
    }

    @Test func noInstalledProvidersShowsEmptyState() async {
        let store = UsageStore(providers: [
            StubProvider(.codex, .success(.notInstalled(.codex, at: now))),
            StubProvider(.claudeCode, .success(.notInstalled(.claudeCode, at: now))),
        ])

        await store.refresh()

        #expect(store.content == .empty)
    }

    @Test func failedRefreshKeepsLastSnapshot() async {
        let good = Fixtures.snapshot(.codex, fiveHour: 74, weekly: 52, at: now)
        let provider = StubProvider(.codex, .success(good))
        let store = UsageStore(providers: [provider])

        await store.refresh()
        await provider.setResult(.failure(ProviderError.refreshFailed(reason: "Offline")))
        await store.refresh()

        let state = store.states.first { $0.provider == .codex }
        #expect(state?.snapshot == good)
        #expect(state?.failure?.message == "Offline")
        #expect(store.hasFailures)
    }

    @Test func successfulRefreshClearsFailure() async {
        let provider = StubProvider(.codex, .failure(ProviderError.refreshFailed(reason: "Offline")))
        let store = UsageStore(providers: [provider])

        await store.refresh()
        #expect(store.states.first?.failure != nil)
        #expect(store.states.first?.isVisible == true)

        await provider.setResult(.success(Fixtures.snapshot(.codex, at: now)))
        await store.refresh()
        #expect(store.states.first?.failure == nil)
        #expect(!store.hasFailures)
    }

    @Test func refreshOnlySelectedProvider() async {
        let codex = StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)))
        let claude = StubProvider(.claudeCode, .success(Fixtures.snapshot(.claudeCode, at: now)))
        let store = UsageStore(providers: [codex, claude])

        await store.refresh(only: [.codex])

        #expect(await codex.fetchCount == 1)
        #expect(await claude.fetchCount == 0)
    }

    @Test func concurrentRefreshesCoalesce() async {
        let provider = StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)), delay: .milliseconds(50))
        let store = UsageStore(providers: [provider])

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)

        #expect(await provider.fetchCount == 1)
    }

    @Test func refreshIfNeededSkipsRecentData() async {
        let provider = StubProvider(.codex, .success(Fixtures.snapshot(.codex, at: now)))
        let clock = TestClock(now)
        let store = UsageStore(providers: [provider], now: { clock.now })

        await store.refresh()
        clock.advance(by: 30)
        await store.refreshIfNeeded(maxAge: 60)
        #expect(await provider.fetchCount == 1)

        clock.advance(by: 60)
        await store.refreshIfNeeded(maxAge: 60)
        #expect(await provider.fetchCount == 2)
    }

    @Test func seededStatesKeepDisplayOrder() {
        let store = UsageStore(
            providers: [],
            states: [
                ProviderState(provider: .claudeCode, snapshot: Fixtures.snapshot(.claudeCode, at: now)),
                ProviderState(provider: .codex, snapshot: Fixtures.snapshot(.codex, at: now)),
            ]
        )
        #expect(store.states.map(\.provider) == [.codex, .claudeCode])
    }
}
