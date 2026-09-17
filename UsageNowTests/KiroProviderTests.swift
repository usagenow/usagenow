import Foundation
import Testing

@testable import UsageNow

/// Fixtures copy the shape Kiro 1.1 writes, with made-up identifiers.
enum KiroFixture {
    static func limitsLine(
        at time: String = "2026-09-17 14:51:46.957",
        title: String = "KIRO FREE",
        used: Double = 1.57,
        limit: Double = 50,
        reset: String = "2026-10-01T00:00:00.000Z",
        trial: String = #"{"freeTrialStatus":"EXPIRED","currentUsage":500,"currentUsageWithPrecision":500,"usageLimit":500,"usageLimitWithPrecision":500,"freeTrialExpiry":"2026-02-27T17:06:13.097Z"}"#,
        bonuses: String = "[]",
        command: String = "GetUsageLimitsCommand"
    ) -> String {
        #"\#(time) [info] {"clientName":"CodeWhispererRuntimeClient","commandName":"\#(command)","input":{"profileArn":"arn:aws:codewhisperer:us-east-1:000000000000:profile/EXAMPLE","origin":"AI_EDITOR","resourceType":"AGENTIC_REQUEST"},"output":{"nextDateReset":"\#(reset)","usageBreakdownList":[{"currentUsage":\#(Int(used)),"currentOverages":0,"usageLimit":\#(Int(limit)),"overageCharges":0,"currency":"USD","resourceType":"CREDIT","displayName":"Credit","displayNamePlural":"Credits","currentUsageWithPrecision":\#(used),"currentOveragesWithPrecision":0,"usageLimitWithPrecision":\#(limit),"unit":"INVOCATIONS","overageRate":0.04,"nextDateReset":"\#(reset)","overageCap":10000,"overageCapWithPrecision":10000,"freeTrialInfo":\#(trial),"bonuses":\#(bonuses),"overageCredits":[]}],"subscriptionInfo":{"type":"Q_DEVELOPER_STANDALONE_FREE","upgradeCapability":"UPGRADE_CAPABLE","overageCapability":"OVERAGE_INCAPABLE","subscriptionManagementTarget":"PURCHASE","subscriptionTitle":"\#(title)"},"overageConfiguration":{"overageStatus":"DISABLED"},"userInfo":{"userId":"d-0000000000.00000000-0000-0000-0000-000000000000"}},"metadata":{"httpStatusCode":200,"requestId":"00000000-0000-0000-0000-000000000000","attempts":1,"totalRetryDelay":0}}"#
    }

    static func usageSummary(id: String, at date: Date, credits: [Double], unit: String = "credit") -> String {
        let turns = credits.map { #"{"unit":"\#(unit)","unitPlural":"\#(unit)s","usage":\#($0),"usedTools":["todo_list"]}"# }.joined(separator: ",")
        return #"{"id":"\#(id)","timestamp":"\#(TestDates.iso(date))","payload":{"type":"usage_summary","promptTurnSummaries":[\#(turns)],"elapsedTime":460676,"status":"success","executionId":"exec-\#(id)","requestIds":["req-\#(id)"]}}"#
    }

    /// Carries the words the parser looks for, to prove content isn't mistaken for usage.
    static func message(id: String, at date: Date) -> String {
        #"{"id":"\#(id)","timestamp":"\#(TestDates.iso(date))","payload":{"type":"assistant","content":"the usage_summary said \"credit\" 99"}}"#
    }

    static func contextUsage(id: String, at date: Date) -> String {
        #"{"id":"\#(id)","timestamp":"\#(TestDates.iso(date))","payload":{"type":"session_metadata","key":"contextUsage","value":{"usagePercentage":2.6468}}}"#
    }
}

struct KiroUsageLimitsParserTests {
    private let now = TestDates.noon

    private func parse(_ line: String) -> KiroUsageLimits? {
        KiroUsageLimitsParser.parse(Data(line.utf8), now: now)
    }

    @Test func readsThePlanCreditsAndReset() throws {
        let limits = try #require(parse(KiroFixture.limitsLine()))
        #expect(limits.planName == "Free")
        #expect(limits.creditsUsed == 1.57)
        #expect(limits.creditsLimit == 50)
        #expect(limits.resetsAt == SessionTimestamp.parse("2026-10-01T00:00:00.000Z"))
        #expect(limits.window.kind == .monthly)
        #expect(limits.window.usage == UsagePercentage(used: 1.57, limit: 50))
    }

    /// Kiro still reports an expired trial, fully used. Counting it would show
    /// a plan with every credit left as exhausted.
    @Test func ignoresAnExpiredTrial() throws {
        let limits = try #require(parse(KiroFixture.limitsLine(used: 0)))
        #expect(limits.creditsUsed == 0)
        #expect(limits.creditsLimit == 50)
    }

    @Test func countsAnActiveTrial() throws {
        let trial = #"{"freeTrialStatus":"ACTIVE","currentUsageWithPrecision":120,"usageLimitWithPrecision":500}"#
        let limits = try #require(parse(KiroFixture.limitsLine(used: 0, trial: trial)))
        #expect(limits.creditsUsed == 120)
        #expect(limits.creditsLimit == 550)
    }

    @Test func countsOnlyActiveBonuses() throws {
        let bonuses = #"[{"status":"ACTIVE","currentUsageWithPrecision":10,"usageLimitWithPrecision":100},{"status":"EXPIRED","currentUsageWithPrecision":200,"usageLimitWithPrecision":200}]"#
        let limits = try #require(parse(KiroFixture.limitsLine(used: 5, bonuses: bonuses)))
        #expect(limits.creditsUsed == 15)
        #expect(limits.creditsLimit == 150)
    }

    @Test func readsTheLocalTimeTheLineWasLogged() throws {
        let limits = try #require(parse(KiroFixture.limitsLine(at: "2026-09-17 14:51:46.957")))
        let expected = DateComponents(
            calendar: .current, timeZone: .current,
            year: 2026, month: 9, day: 17, hour: 14, minute: 51, second: 46, nanosecond: 957_000_000
        ).date!
        #expect(abs(limits.observedAt.timeIntervalSince(expected)) < 0.001)
    }

    @Test func ignoresOtherCommandsAndBrokenLines() {
        #expect(parse(KiroFixture.limitsLine(command: "InvokeMCPCommand")) == nil)
        #expect(parse(#"2026-09-17 14:51:46.957 [info] {"commandName":"GetUsageLimitsCommand""#) == nil)
        #expect(parse("GetUsageLimitsCommand without a timestamp or a body") == nil)
        #expect(parse(KiroFixture.limitsLine(limit: 0)) == nil)
    }

    @Test func namesPlans() {
        #expect(KiroUsageLimitsParser.planName(from: "KIRO FREE") == "Free")
        #expect(KiroUsageLimitsParser.planName(from: "KIRO PRO+") == "Pro+")
        #expect(KiroUsageLimitsParser.planName(from: "KIRO POWER") == "Power")
        #expect(KiroUsageLimitsParser.planName(from: "KIRO ") == nil)
    }
}

struct KiroUsageLimitsReaderTests {
    private func log(_ dir: TemporaryDirectory, launch: String, window: String = "window1", lines: [String]) throws {
        try dir.write("\(launch)/\(window)/exthost/kiro.kiroAgent/q-client.log", text: lines.joined(separator: "\n") + "\n")
    }

    @Test func takesTheNewestAnswerFromTheNewestLaunch() throws {
        let dir = try TemporaryDirectory()
        try log(dir, launch: "20260910T090000", lines: [KiroFixture.limitsLine(at: "2026-09-10 09:00:00.000", used: 40)])
        try log(dir, launch: "20260917T144951", lines: [
            KiroFixture.limitsLine(at: "2026-09-17 14:51:46.957", used: 1),
            KiroFixture.limitsLine(at: "2026-09-17 15:02:26.000", used: 1.57),
        ])
        try log(dir, launch: "20260917T144951", window: "window2", lines: [KiroFixture.limitsLine(at: "2026-09-17 14:55:00.000", used: 1.2)])

        let limits = try #require(KiroUsageLimitsReader.latest(in: dir.url))
        #expect(limits.creditsUsed == 1.57)
    }

    @Test func fallsBackToAnOlderLaunchWhenTheNewestHasNoAnswer() throws {
        let dir = try TemporaryDirectory()
        try log(dir, launch: "20260910T090000", lines: [KiroFixture.limitsLine(used: 12)])
        try log(dir, launch: "20260917T144951", lines: [KiroFixture.limitsLine(command: "InvokeMCPCommand")])

        #expect(KiroUsageLimitsReader.latest(in: dir.url)?.creditsUsed == 12)
    }

    @Test func noLogsMeansNoLimits() throws {
        let dir = try TemporaryDirectory()
        #expect(KiroUsageLimitsReader.latest(in: dir.url) == nil)
        #expect(KiroUsageLimitsReader.latest(in: dir.url.appending(path: "missing")) == nil)
    }
}

struct KiroSessionReaderTests {
    private let noon = TestDates.noon
    private var since: Date { TestDates.utc.startOfDay(for: noon) }

    @Test func sumsTodaysCreditsAndTurns() async throws {
        let dir = try TemporaryDirectory()
        _ = try dir.writeJSONL("sessions/abc/sess_1/messages.jsonl", lines: [
            KiroFixture.contextUsage(id: "c1", at: noon.addingTimeInterval(-900)),
            KiroFixture.message(id: "m1", at: noon.addingTimeInterval(-800)),
            KiroFixture.usageSummary(id: "u1", at: noon.addingTimeInterval(-700), credits: [1.25, 0.25]),
            KiroFixture.usageSummary(id: "u2", at: noon.addingTimeInterval(-600), credits: [2]),
        ], modified: noon)
        _ = try dir.writeJSONL("sessions/def/sess_2/messages.jsonl", lines: [
            KiroFixture.usageSummary(id: "u3", at: noon.addingTimeInterval(-500), credits: [0.5]),
        ], modified: noon)

        let result = await KiroSessionReader().todaysActivity(root: dir.url.appending(path: "sessions"), since: since)
        #expect(result.credits == 4)
        #expect(result.turns == 3)
    }

    @Test func ignoresYesterdayOtherUnitsAndDuplicates() async throws {
        let dir = try TemporaryDirectory()
        let summary = KiroFixture.usageSummary(id: "u1", at: noon, credits: [3])
        _ = try dir.writeJSONL("sessions/abc/sess_1/messages.jsonl", lines: [
            KiroFixture.usageSummary(id: "old", at: since.addingTimeInterval(-60), credits: [9]),
            KiroFixture.usageSummary(id: "u2", at: noon, credits: [7], unit: "token"),
            summary,
        ], modified: noon)
        // A copied session repeats the same record.
        _ = try dir.writeJSONL("sessions/abc/sess_copy/messages.jsonl", lines: [summary], modified: noon)

        let result = await KiroSessionReader().todaysActivity(root: dir.url.appending(path: "sessions"), since: since)
        #expect(result.credits == 3)
        #expect(result.turns == 2)
    }
}

struct KiroProviderTests {
    private let noon = TestDates.noon

    private func environment(_ dir: TemporaryDirectory, installed: Bool = true) -> KiroEnvironment {
        KiroEnvironment(
            home: dir.url.appending(path: ".kiro"),
            homeExists: installed,
            logsRoot: dir.url.appending(path: "logs"),
            application: nil
        )
    }

    private func provider(_ environment: KiroEnvironment, limits: KiroUsageLimits?) -> KiroProvider {
        KiroProvider(
            discover: { environment },
            readLimits: { _ in limits },
            now: { [noon] in noon },
            calendar: TestDates.utc
        )
    }

    private func limits(used: Double, resetsAt: Date?) -> KiroUsageLimits {
        KiroUsageLimits(planName: "Free", creditsUsed: used, creditsLimit: 50, resetsAt: resetsAt, observedAt: noon.addingTimeInterval(-3_600))
    }

    @Test func notInstalled() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, installed: false), limits: nil).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notInstalled)
    }

    @Test func showsTheMonthlyLimitWithWhenItWasRead() async throws {
        let dir = try TemporaryDirectory()
        let reading = limits(used: 10, resetsAt: noon.addingTimeInterval(86_400 * 10))
        let snapshot = try await provider(environment(dir), limits: reading).fetchSnapshot(trigger: .automatic)

        #expect(snapshot.planName == "Free")
        #expect(snapshot.windows.map(\.kind) == [.monthly])
        #expect(snapshot.windows.first?.usage == UsagePercentage(used: 10, limit: 50))
        #expect(snapshot.quotaUnavailableReason == nil)
        #expect(snapshot.limitsUpdatedAt == reading.observedAt)
    }

    /// Last month's reading says nothing about this month.
    @Test func aReadingFromBeforeTheResetLosesItsPercentage() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir), limits: limits(used: 48, resetsAt: noon.addingTimeInterval(-60))).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.first?.usage == nil)
        #expect(snapshot.quotaUnavailableReason == .toolNotRunning)
    }

    @Test func withoutAReadingItAsksToOpenKiro() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir), limits: nil).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.quotaUnavailableReason == .toolNotRunning)
        #expect(snapshot.activity.creditsToday == 0)
        #expect(snapshot.activity.requestsToday == 0)
    }
}
