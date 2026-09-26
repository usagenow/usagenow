import Foundation
import Testing

@testable import UsageNow

/// Lines in the shape Qoder 0.4 writes to `~/.qoder/projects/**.jsonl`.
enum QoderFixture {
    static func answer(_ date: Date, request: String, credits: Double, billable: Bool = true) -> String {
        #"{"parentUuid":"p","isSidechain":false,"type":"assistant","timestamp":"\#(TestDates.iso(date))","sessionId":"s1","cwd":"/Users/me/secret-project","model":"qmodel_38max","message":{"id":"msg-\#(request)","type":"message","role":"assistant","model":"qmodel_38max","content":[{"type":"text","text":"a reply that mentions \"credits\": 999"}],"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"service_tier":"standard","credits":\#(credits),"original_credits":\#(credits * 2.5),"billable":\#(billable),"request_id":"\#(request)","context_usage_ratio":0.12}}}"#
    }

    static func prompt(_ date: Date) -> String {
        #"{"type":"user","timestamp":"\#(TestDates.iso(date))","message":{"role":"user","content":"how many credits do I have? \"credits\": 5"}}"#
    }
}

struct QoderSessionReaderTests {
    private let noon = TestDates.noon
    private var period: ActivityPeriod { ActivityPeriod(now: noon, calendar: TestDates.utc) }

    @Test func sumsTodaysCreditsAndAnswers() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("projects/-Users-me-app/s1.jsonl", lines: [
            QoderFixture.prompt(noon.addingTimeInterval(-700)),
            QoderFixture.answer(noon.addingTimeInterval(-600), request: "r1", credits: 1.0936714285714284),
            QoderFixture.answer(noon.addingTimeInterval(-500), request: "r2", credits: 0.25),
            QoderFixture.answer(noon.addingTimeInterval(-86_400), request: "r0", credits: 3),
        ], modified: noon)

        let result = await QoderSessionReader().activity(root: dir.url.appending(path: "projects"), period: period)
        #expect(result.requests == 2)
        #expect(result.credits == Decimal(string: "1.3436714285714284"))
        #expect(result.history.metric == .credits)
        #expect(result.history.days.compactMap(\.credits).suffix(2) == [3, Decimal(string: "1.3436714285714284")!])
        #expect(result.hasSessionFiles)
    }

    /// A resumed session repeats earlier answers; each request counts once.
    @Test func countsARequestOnce() async throws {
        let dir = try TemporaryDirectory()
        let answer = QoderFixture.answer(noon, request: "r1", credits: 2)
        try dir.writeJSONL("projects/a/s1.jsonl", lines: [answer], modified: noon)
        try dir.writeJSONL("projects/a/s2.jsonl", lines: [answer], modified: noon)

        let result = await QoderSessionReader().activity(root: dir.url.appending(path: "projects"), period: period)
        #expect(result.requests == 1)
        #expect(result.credits == 2)
    }

    @Test func anAnswerThatIsntBillableCostsNothing() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("projects/a/s1.jsonl", lines: [
            QoderFixture.answer(noon, request: "free", credits: 4, billable: false),
        ], modified: noon)

        let result = await QoderSessionReader().activity(root: dir.url.appending(path: "projects"), period: period)
        #expect(result.requests == 1)
        #expect(result.credits == 0)
    }
}

struct QoderProviderTests {
    private let noon = TestDates.noon

    private func provider(_ environment: QoderEnvironment) -> QoderProvider {
        QoderProvider(discover: { environment }, now: { [noon] in noon }, calendar: TestDates.utc)
    }

    @Test func notInstalled() async throws {
        let environment = QoderEnvironment(home: URL(filePath: "/nonexistent"), homeExists: false, application: nil, executable: nil)
        #expect(try await provider(environment).fetchSnapshot(trigger: .automatic).status == .notInstalled)
    }

    @Test func showsCreditsAndNoLimits() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL(".qoder/projects/a/s1.jsonl", lines: [QoderFixture.answer(noon, request: "r1", credits: 1.5)], modified: noon)
        let environment = QoderEnvironment.discover(homeDirectory: dir.url)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.activity.creditsToday == Decimal(string: "1.5"))
        #expect(snapshot.activity.requestsToday == 1)
        #expect(snapshot.activity.tokensToday == nil, "Qoder zeroes tokens, so none are shown")
        #expect(snapshot.recentModel == nil, "An internal alias isn't a model name")
    }

    @Test func installedButNeverUsedShowsAQuietDay() async throws {
        let dir = try TemporaryDirectory()
        try dir.write(".qoder/settings.json", text: "{}")
        let snapshot = try await provider(QoderEnvironment.discover(homeDirectory: dir.url)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.activity.creditsToday == 0)
        #expect(snapshot.activity.requestsToday == 0)
    }
}
