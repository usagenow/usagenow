import Foundation
import Testing
@testable import UsageNow

/// What the Claude card shows when its last reading is old: windows that
/// reset stay visible without a percentage, and a limit Claude Code hit is
/// read from its own transcript, no sign-in needed.
struct ClaudeResetAndLimitHitTests {
    private let noon = TestDates.noon

    private func environment(_ dir: TemporaryDirectory) throws -> ClaudeCodeEnvironment {
        try dir.write(".claude.json", text: ClaudeProfileFixture.pro)
        return ClaudeCodeEnvironment(
            configDirectory: dir.url.appending(path: ".claude"),
            globalConfigFile: dir.url.appending(path: ".claude.json"),
            configDirectoryExists: true,
            configDirectoryIsReadable: true,
            globalConfigExists: true,
            executable: nil
        )
    }

    private func provider(_ environment: ClaudeCodeEnvironment, client: ClaudeUsageLimitsClient? = nil, at date: Date) -> ClaudeCodeProvider {
        ClaudeCodeProvider(discover: { environment }, limitsClient: client, limitsEnabled: FeatureSwitch(client != nil), now: { date }, calendar: TestDates.utc)
    }

    private static func limitHit(_ date: Date, type: String = "five_hour", status: String = "rejected", resetsAt: Date) -> String {
        #"{"type":"assistant","timestamp":"\#(TestDates.iso(date))","isApiErrorMessage":true,"message":{"id":"err","model":"<synthetic>","content":[{"type":"text","text":"You've hit your limit"}],"usage":{"input_tokens":0,"output_tokens":0}},"quotaLimits":{"status":"\#(status)","resetsAt":\#(Int(resetsAt.timeIntervalSince1970)),"unifiedRateLimitFallbackAvailable":false,"rateLimitType":"\#(type)","overageStatus":"rejected","overageDisabledReason":"org_level_disabled","upgradePaths":[],"isUsingOverage":false}}"#
    }

    // MARK: Windows that reset after the last reading

    @Test func asOfKeepsTheRowButForgetsTheUsage() {
        let windows = [
            UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 40), resetsAt: noon.addingTimeInterval(-60)),
            UsageWindow(kind: .weekly, usage: UsagePercentage(percent: 20), resetsAt: noon.addingTimeInterval(86_400)),
        ].asOf(noon)
        #expect(windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(windows[0].usage == nil)
        #expect(windows[1].usage?.displayValue == 20)
        #expect(windows.mostRelevant?.kind == .weekly, "An unknown window never counts as the tightest")
    }

    @Test func aResetFiveHourWindowStaysVisibleWithTheReason() async throws {
        let dir = try TemporaryDirectory()
        let memory = MemoryQuotaStore()
        // Read at noon; the 5-hour window resets at 15:00 and the sign-in has expired since.
        _ = await ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fresh"), transport: StubTransport(status: 200, body: ClaudeUsageFixture.full), lastKnownLimits: memory.store)
            .windows(trigger: .manual, now: { TestDates.noon })
        let later = ClaudeUsageLimitsClient(
            credentials: StubCredentials(token: "stale", expiresAt: noon),
            transport: StubTransport(status: 200, body: ClaudeUsageFixture.full),
            lastKnownLimits: memory.store,
            requestSignInRefresh: { false }
        )

        let evening = noon.addingTimeInterval(6 * 3_600)
        let snapshot = try await provider(environment(dir), client: later, at: evening).fetchSnapshot(trigger: .automatic)

        let fiveHour = try #require(snapshot.window(.fiveHour))
        #expect(fiveHour.usage == nil, "Nothing says how much of the new window is used")
        #expect(snapshot.window(.weekly)?.usage != nil)
        #expect(snapshot.mostCriticalWindow?.kind == .weekly)
        #expect(snapshot.limitsUpdatedAt == noon)
        #expect(snapshot.quotaUnavailableReason == nil, "A current weekly reading still counts")
    }

    @Test func reasonShowsWhenNoWindowHasCurrentUsage() async throws {
        let dir = try TemporaryDirectory()
        let memory = MemoryQuotaStore()
        memory.store.save(QuotaCacheEntry(value: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 50), resetsAt: noon.addingTimeInterval(3_600))], fetchedAt: noon))
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "stale", expiresAt: noon), transport: StubTransport(status: 200, body: "{}"), lastKnownLimits: memory.store)

        let snapshot = try await provider(environment(dir), client: client, at: noon.addingTimeInterval(2 * 3_600)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.quotaUnavailableReason == .signInExpired, "The way to fix it stays on screen")
    }

    @Test func passedResetIsDescribedWithoutACountdown() {
        let formatter = ResetTimeFormatter(calendar: TestDates.utc, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!)
        #expect(formatter.passedResetDescription(for: noon) == "Reset Fri 12:00 · not updated since")
    }

    @MainActor
    @Test func widgetLeavesOutWindowsKnownOnlyToHaveReset() {
        let snapshot = ProviderSnapshot(
            provider: .claudeCode,
            status: .available,
            windows: [
                UsageWindow(kind: .fiveHour, usage: nil, resetsAt: noon.addingTimeInterval(-60)),
                UsageWindow(kind: .weekly, usage: UsagePercentage(percent: 15), resetsAt: noon.addingTimeInterval(86_400)),
            ],
            updatedAt: noon
        )
        let widget = WidgetSnapshotWriter.makeSnapshot(states: [ProviderState(provider: .claudeCode, snapshot: snapshot)], enabledProviders: [.claudeCode], generatedAt: noon)
        #expect(widget.providers.first?.windows.map(\.kind) == [.weekly])
    }

    // MARK: Limits Claude Code reported hitting

    @Test func aLimitHitShowsTheWindowAsUsedUpWithoutAnySignIn() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir)
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            ClaudeFixture.assistant(noon.addingTimeInterval(-600), messageID: "m1", requestID: "r1"),
            Self.limitHit(noon.addingTimeInterval(-60), resetsAt: noon.addingTimeInterval(2 * 3_600)),
        ], modified: noon)

        let snapshot = try await provider(environment, at: noon).fetchSnapshot(trigger: .automatic)
        let fiveHour = try #require(snapshot.window(.fiveHour))
        #expect(fiveHour.usage?.remainingDisplayValue == 0)
        #expect(fiveHour.resetsAt == noon.addingTimeInterval(2 * 3_600))
        #expect(snapshot.limitsUpdatedAt == noon.addingTimeInterval(-60))
        #expect(snapshot.activity.requestsToday == 1, "The notice itself isn't a request")
        #expect(snapshot.mostCriticalWindow?.kind == .fiveHour)
    }

    @Test func aHitReplacesAnOlderReadingButNotANewerOne() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir)
        let memory = MemoryQuotaStore()
        let reset = noon.addingTimeInterval(3 * 3_600)
        memory.store.save(QuotaCacheEntry(value: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 60), resetsAt: reset)], fetchedAt: noon))
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "stale", expiresAt: noon), transport: StubTransport(status: 200, body: "{}"), lastKnownLimits: memory.store)

        try dir.writeJSONL(".claude/projects/p/older.jsonl", lines: [Self.limitHit(noon.addingTimeInterval(-3_600), resetsAt: reset)], modified: noon)
        #expect(try await provider(environment, client: client, at: noon.addingTimeInterval(60)).fetchSnapshot(trigger: .automatic).window(.fiveHour)?.usage?.displayValue == 60)

        try dir.writeJSONL(".claude/projects/p/newer.jsonl", lines: [Self.limitHit(noon.addingTimeInterval(1_800), resetsAt: reset)], modified: noon.addingTimeInterval(1_800))
        let snapshot = try await provider(environment, client: client, at: noon.addingTimeInterval(2_000)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.window(.fiveHour)?.usage?.displayValue == 100)
    }

    @Test func pastOrUnrelatedNoticesAreIgnored() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            Self.limitHit(noon.addingTimeInterval(-7_200), resetsAt: noon.addingTimeInterval(-60)),
            Self.limitHit(noon.addingTimeInterval(-60), status: "allowed_warning", resetsAt: noon.addingTimeInterval(3_600)),
            Self.limitHit(noon.addingTimeInterval(-50), type: "something_new", resetsAt: noon.addingTimeInterval(3_600)),
            #"{"type":"user","timestamp":"\#(TestDates.iso(noon))","message":{"content":"lorem \"quotaLimits\":{\"status\":\"rejected\"}"}}"#,
        ], modified: noon)
        let snapshot = try await provider(environment(dir), at: noon).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func weeklyHitsAreRecognizedToo() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            Self.limitHit(noon.addingTimeInterval(-60), type: "seven_day_opus", resetsAt: noon.addingTimeInterval(3 * 86_400)),
        ], modified: noon)
        let snapshot = try await provider(environment(dir), at: noon).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.first?.kind == .weekly)
        #expect(snapshot.windows.first?.scope == "Opus")
    }
}
