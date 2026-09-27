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

    /// Switching between "left" and "used" redraws the widget even when the
    /// numbers are the same.
    @Test func carriesTheUsageAmountStyle() throws {
        let directory = try TemporaryDirectory()
        let store = WidgetSnapshotStore(directory: directory.url)
        let reloads = Counter()
        let writer = WidgetSnapshotWriter(store: store, reloadTimelines: { reloads.increment() }, now: { self.now })
        let states = [state(.codex, windows: [window(.weekly, used: 42)])]

        writer.update(states: states, enabledProviders: [.codex], style: .remaining)
        writer.update(states: states, enabledProviders: [.codex], style: .used)
        #expect(reloads.value == 2)
        #expect(store.read()?.usageAmountStyle == .used)
    }

    /// Tools that meter in credits show them where there are no limits.
    @Test func carriesCreditsForProvidersWithoutTokens() {
        var qoder = ProviderState(provider: .qoder)
        qoder.snapshot = ProviderSnapshot(
            provider: .qoder,
            status: .available,
            activity: LocalActivity(requestsToday: 7, creditsToday: Decimal(string: "2.2325")),
            updatedAt: now
        )
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [qoder], enabledProviders: [.qoder], generatedAt: now)
        let provider = snapshot.providers.first
        #expect(provider?.creditsToday == Decimal(string: "2.2325"))
        #expect(provider?.activityText(short: true)?.contains("credits") == true)
    }

    /// A newer app may name a provider, window, or reason this widget
    /// doesn't know. Those are skipped; everything else still shows.
    @Test func readsASnapshotFromANewerApp() throws {
        var codex = ProviderState(provider: .codex)
        codex.snapshot = ProviderSnapshot(
            provider: .codex,
            status: .available,
            windows: [UsageWindow(kind: .weekly, usage: UsagePercentage(percent: 42), resetsAt: now.addingTimeInterval(86_400))],
            updatedAt: now
        )
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [codex], enabledProviders: [.codex], generatedAt: now)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder.widget.encode(snapshot)) as? [String: Any])
        var state = try #require(json["state"] as? [String: Any])
        var payload = try #require(state["providers"] as? [String: Any])
        var providers = try #require(payload["_0"] as? [[String: Any]])
        var known = providers[0]
        var windows = try #require(known["windows"] as? [Any])
        windows.append(["kind": "decade", "usage": 10])
        known["windows"] = windows
        known["quotaUnavailableReason"] = "somethingNew"
        providers[0] = known
        providers.append(["provider": "futuretool", "windows": []])
        payload["_0"] = providers
        state["providers"] = payload
        json["state"] = state

        let decoded = try JSONDecoder.widget.decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.providers.map(\.provider) == [.codex])
        #expect(decoded.providers.first?.windows.map(\.kind) == [.weekly])
        #expect(decoded.providers.first?.quotaUnavailableReason == nil)
    }

    /// Reading got more forgiving; writing didn't change, so an older widget
    /// still reads what this app writes.
    @Test func theWrittenShapeIsUnchanged() throws {
        var codex = ProviderState(provider: .codex)
        codex.snapshot = ProviderSnapshot(provider: .codex, status: .available, updatedAt: now)
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [codex], enabledProviders: [.codex], generatedAt: now)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder.widget.encode(snapshot)) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        let payload = try #require(state["providers"] as? [String: Any])
        #expect(Set(payload.keys) == ["_0"])
        #expect(try JSONDecoder.widget.decode(WidgetSnapshot.self, from: JSONEncoder.widget.encode(snapshot)) == snapshot)

        for empty in [WidgetSnapshot.State.noProvidersEnabled, .noProvidersDetected] {
            let other = WidgetSnapshot(generatedAt: now, state: empty)
            #expect(try JSONDecoder.widget.decode(WidgetSnapshot.self, from: JSONEncoder.widget.encode(other)) == other)
        }
    }

    /// A snapshot written before the choice existed still reads, as "left".
    @Test func olderSnapshotsHaveNoStyle() throws {
        var snapshot = WidgetSnapshot(generatedAt: now, state: .noProvidersEnabled)
        snapshot.usageAmountStyle = .used
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder.widget.encode(snapshot)) as? [String: Any])
        json["usageAmountStyle"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder.widget.decode(WidgetSnapshot.self, from: data)
        #expect(decoded.usageAmountStyle == nil)
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
        var snapshot = makeSnapshot()
        snapshot.usageAmountStyle = .used
        let data = try JSONEncoder.widget.encode(snapshot)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["schemaVersion", "generatedAt", "state", "usageAmountStyle"])

        var keys = Set<String>()
        collectKeys(json, into: &keys)
        let allowed: Set<String> = [
            "schemaVersion", "generatedAt", "state", "usageAmountStyle", "providers", "_0",
            "provider", "planName", "modelName", "windows", "tokensToday", "requestsToday", "creditsToday",
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
