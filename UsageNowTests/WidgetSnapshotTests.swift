import Foundation
import Synchronization
import Testing
@testable import UsageNow

@MainActor
struct WidgetSnapshotWriterTests {
    private let now = TestDates.noon

    private func state(_ provider: ProviderID, windows: [UsageWindow], status: ProviderStatus = .available) -> ProviderState {
        ProviderState(
            provider: provider,
            snapshot: ProviderSnapshot(
                provider: provider,
                status: status,
                planName: "Pro",
                recentModel: "example-model-1",
                windows: windows,
                activity: LocalActivity(tokensToday: 1_000_000, requestsToday: 10),
                updatedAt: now
            )
        )
    }

    private func window(_ kind: UsageWindowKind, used: Double, resetsIn seconds: TimeInterval = 3_600) -> UsageWindow {
        UsageWindow(kind: kind, usage: UsagePercentage(percent: used), resetsAt: now.addingTimeInterval(seconds))
    }

    @Test func convertsEnabledProviders() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            states: [state(.codex, windows: [window(.weekly, used: 42)]), state(.claudeCode, windows: [window(.fiveHour, used: 89)])],
            enabledProviders: [.codex, .claudeCode],
            generatedAt: now
        )
        #expect(snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion)
        #expect(snapshot.providers.map(\.provider) == [.codex, .claudeCode])
        #expect(snapshot.providers.first?.planName == "Pro")
        #expect(snapshot.providers.first?.windows.first?.usage?.remainingDisplayValue == 58)
    }

    @Test func dropsDisabledProviders() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            states: [state(.codex, windows: []), state(.claudeCode, windows: [])],
            enabledProviders: [.claudeCode],
            generatedAt: now
        )
        #expect(snapshot.providers.map(\.provider) == [.claudeCode])
    }

    @Test func dropsProvidersThatArentInstalled() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            states: [state(.codex, windows: [], status: .notInstalled), state(.claudeCode, windows: [window(.weekly, used: 10)])],
            enabledProviders: [.codex, .claudeCode],
            generatedAt: now
        )
        #expect(snapshot.providers.map(\.provider) == [.claudeCode])
    }

    @Test func noProvidersEnabledState() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [state(.codex, windows: [])], enabledProviders: [], generatedAt: now)
        #expect(snapshot.state == .noProvidersEnabled)
        #expect(snapshot.providers.isEmpty)
    }

    @Test func noProvidersDetectedState() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            states: [state(.codex, windows: [], status: .notInstalled)],
            enabledProviders: [.codex],
            generatedAt: now
        )
        #expect(snapshot.state == .noProvidersDetected)
    }

    @Test func keepsTheReasonWhenQuotaIsMissing() {
        var missing = state(.claudeCode, windows: [])
        missing.snapshot?.quotaUnavailableReason = .signInExpired
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [missing], enabledProviders: [.claudeCode], generatedAt: now)
        #expect(snapshot.providers.first?.quotaUnavailableReason == .signInExpired)
        #expect(snapshot.providers.first?.tokensToday == 1_000_000)
    }

    @Test func mostRelevantWindowIsTheTightestThenSoonest() {
        let provider = WidgetSnapshotWriter.makeSnapshot(
            states: [state(.claudeCode, windows: [
                window(.weekly, used: 34, resetsIn: 3 * 86_400),
                window(.fiveHour, used: 89, resetsIn: 3_600),
            ])],
            enabledProviders: [.claudeCode],
            generatedAt: now
        ).providers.first

        #expect(provider?.mostRelevantWindow?.kind == .fiveHour)

        // Equal remaining: the one resetting sooner wins.
        let tie = [
            UsageWindow(kind: .weekly, usage: UsagePercentage(percent: 50), resetsAt: now.addingTimeInterval(86_400)),
            UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 50), resetsAt: now.addingTimeInterval(600)),
        ]
        #expect(tie.mostRelevant?.kind == .fiveHour)

        // Windows with unknown usage are ignored.
        let unknown = [UsageWindow(kind: .weekly, usage: nil, resetsAt: nil), window(.fiveHour, used: 10)]
        #expect(unknown.mostRelevant?.kind == .fiveHour)
    }

    @Test func nextResetIsTheSoonestUpcoming() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            states: [
                state(.codex, windows: [window(.weekly, used: 42, resetsIn: 4 * 86_400)]),
                state(.claudeCode, windows: [window(.fiveHour, used: 20, resetsIn: 3_600)]),
            ],
            enabledProviders: [.codex, .claudeCode],
            generatedAt: now
        )
        let next = snapshot.nextReset(after: now)
        #expect(next?.provider == .claudeCode)
        #expect(next?.resetsAt == now.addingTimeInterval(3_600))
        // Resets already in the past don't count.
        #expect(snapshot.nextReset(after: now.addingTimeInterval(5 * 86_400)) == nil)
    }

    @Test func staleness() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [], enabledProviders: [.codex], generatedAt: now)
        #expect(!snapshot.isStale(at: now.addingTimeInterval(5 * 60)))
        #expect(snapshot.isStale(at: now.addingTimeInterval(18 * 60)))
    }

    @Test func writesAndReloadsOnlyWhenTheContentChanges() throws {
        let directory = try TemporaryDirectory()
        let store = WidgetSnapshotStore(directory: directory.url)
        let reloads = Counter()
        let writer = WidgetSnapshotWriter(store: store, reloadTimelines: { reloads.increment() }, now: { self.now })

        writer.update(states: [state(.codex, windows: [window(.weekly, used: 42)])], enabledProviders: [.codex])
        #expect(reloads.value == 1)

        // Same content again: no rewrite, no reload.
        writer.update(states: [state(.codex, windows: [window(.weekly, used: 42)])], enabledProviders: [.codex])
        #expect(reloads.value == 1)

        writer.update(states: [state(.codex, windows: [window(.weekly, used: 43)])], enabledProviders: [.codex])
        #expect(reloads.value == 2)
        #expect(store.read()?.providers.first?.windows.first?.usage?.displayValue == 43)
    }

    @Test func missingAppGroupIsNotFatal() {
        let writer = WidgetSnapshotWriter(store: nil, reloadTimelines: { Issue.record("Must not reload without a store") }, now: { self.now })
        writer.update(states: [state(.codex, windows: [])], enabledProviders: [.codex])
    }
}

struct WidgetSnapshotStoreTests {
    private let now = TestDates.noon

    private func makeSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: now, state: .providers([
            WidgetProviderSnapshot(
                provider: .codex,
                planName: "Plus",
                modelName: "example-model-1",
                windows: [UsageWindow(kind: .weekly, usage: UsagePercentage(percent: 42), resetsAt: now.addingTimeInterval(3_600))],
                tokensToday: 12_800_000,
                requestsToday: 47
            ),
        ]))
    }

    @Test func roundTrip() throws {
        let directory = try TemporaryDirectory()
        let store = WidgetSnapshotStore(directory: directory.url)
        let snapshot = makeSnapshot()
        try store.write(snapshot)
        #expect(store.read() == snapshot)
    }

    @Test func missingFileReadsAsNil() throws {
        let directory = try TemporaryDirectory()
        #expect(WidgetSnapshotStore(directory: directory.url).read() == nil)
    }

    @Test func corruptFileReadsAsNil() throws {
        let directory = try TemporaryDirectory()
        let store = WidgetSnapshotStore(directory: directory.url)
        try Data("{ not json".utf8).write(to: store.fileURL)
        #expect(store.read() == nil)
    }

    @Test func newerSchemaIsRefused() throws {
        let directory = try TemporaryDirectory()
        let store = WidgetSnapshotStore(directory: directory.url)
        var snapshot = makeSnapshot()
        snapshot.schemaVersion = WidgetSnapshot.currentSchemaVersion + 1
        try store.write(snapshot)
        #expect(store.read() == nil, "A newer snapshot must send the user to the app instead of being guessed at")
    }

    @Test func replacingASnapshotLeavesNoPartialFile() throws {
        let directory = try TemporaryDirectory()
        let store = WidgetSnapshotStore(directory: directory.url)
        try store.write(makeSnapshot())
        var second = makeSnapshot()
        second.generatedAt = now.addingTimeInterval(60)
        try store.write(second)
        #expect(store.read()?.generatedAt == second.generatedAt)
    }

    /// The snapshot file is the app's only channel to the widget, so its
    /// shape is pinned: nothing outside this list may ever be written.
    @Test func onlySafeFieldsAreSerialized() throws {
        let data = try JSONEncoder.widget.encode(makeSnapshot())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["schemaVersion", "generatedAt", "state"])

        var keys = Set<String>()
        collectKeys(json, into: &keys)
        let allowed: Set<String> = [
            "schemaVersion", "generatedAt", "state", "providers", "_0",
            "provider", "planName", "modelName", "windows", "tokensToday", "requestsToday",
            "quotaUnavailableReason", "kind", "scope", "usage", "resetsAt",
        ]
        #expect(keys.subtracting(allowed).isEmpty, "Unexpected fields: \(keys.subtracting(allowed))")

        // Aggregate counts like "tokensToday" are fine; secrets and
        // identifiers are not.
        let text = String(decoding: data, as: UTF8.self)
        let forbidden = ["accessToken", "refreshToken", "credential", "Bearer", "apiKey", "sk-", "@", "/Users/", "sessionId", "projectPath", "prompt", "cwd"]
        for needle in forbidden {
            #expect(!text.contains(needle), "Snapshot JSON must not contain \(needle)")
        }
    }

    private func collectKeys(_ value: Any, into keys: inout Set<String>) {
        if let object = value as? [String: Any] {
            keys.formUnion(object.keys)
            object.values.forEach { collectKeys($0, into: &keys) }
        } else if let array = value as? [Any] {
            array.forEach { collectKeys($0, into: &keys) }
        }
    }
}

struct WidgetTimelineTests {
    private let now = TestDates.noon

    @Test func refreshesAtTheIdleIntervalWithoutResets() {
        let snapshot = WidgetSnapshot(generatedAt: now, state: .noProvidersEnabled)
        let next = WidgetRefreshSchedule.next(after: now, snapshot: snapshot)
        #expect(next == now.addingTimeInterval(WidgetRefreshSchedule.idleInterval))
    }

    @Test func refreshesJustAfterANearReset() {
        let snapshot = WidgetSnapshot(generatedAt: now, state: .providers([
            WidgetProviderSnapshot(
                provider: .codex,
                windows: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 50), resetsAt: now.addingTimeInterval(300))]
            ),
        ]))
        let next = WidgetRefreshSchedule.next(after: now, snapshot: snapshot)
        #expect(next == now.addingTimeInterval(300 + WidgetRefreshSchedule.minimumInterval))
    }

    @Test func neverSchedulesTighterThanTheMinimum() {
        let snapshot = WidgetSnapshot(generatedAt: now, state: .providers([
            WidgetProviderSnapshot(
                provider: .codex,
                windows: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 50), resetsAt: now.addingTimeInterval(1))]
            ),
        ]))
        let next = WidgetRefreshSchedule.next(after: now, snapshot: snapshot)
        #expect(next >= now.addingTimeInterval(WidgetRefreshSchedule.minimumInterval))
    }

    @Test func noSnapshotStillSchedules() {
        #expect(WidgetRefreshSchedule.next(after: now, snapshot: nil) > now)
    }
}

/// A tiny thread-safe counter for callbacks.
final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func increment() { count.withLock { $0 += 1 } }
}
