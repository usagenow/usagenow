import Foundation
import Testing

@testable import UsageNow

/// Lines in the shapes Qwen Code, Grok Build, and Cline write, taken from
/// their sources. Fabricated: no real prompts, projects, or accounts.
enum NewProviderFixture {
    static func qwenAnswer(_ date: Date, uuid: String, model: String = "qwen3-coder-plus", prompt: Int, cached: Int, output: Int, thoughts: Int = 0) -> String {
        #"{"uuid":"\#(uuid)","parentUuid":"p","sessionId":"s1","timestamp":"\#(TestDates.iso(date))","type":"assistant","cwd":"/Users/me/secret-project","version":"0.9.0","model":"\#(model)","message":{"role":"model","parts":[{"text":"a reply that mentions \"usageMetadata\""}]},"usageMetadata":{"promptTokenCount":\#(prompt),"candidatesTokenCount":\#(output),"cachedContentTokenCount":\#(cached),"thoughtsTokenCount":\#(thoughts),"totalTokenCount":\#(prompt + output + thoughts)}}"#
    }

    static func qwenPrompt(_ date: Date) -> String {
        #"{"uuid":"u0","sessionId":"s1","timestamp":"\#(TestDates.iso(date))","type":"user","message":{"role":"user","parts":[{"text":"what does \"usageMetadata\" mean?"}]}}"#
    }

    static func grokTurn(_ date: Date, prompt: String, models: String, incomplete: Bool = false) -> String {
        #"{"timestamp":\#(Int(date.timeIntervalSince1970)),"method":"_x.ai/session/update","params":{"sessionId":"g1","update":{"sessionUpdate":"turn_completed","prompt_id":"\#(prompt)","stop_reason":"end_turn","agent_result":"the final answer, with \"turn_completed\" in it","usage":{"inputTokens":1,"outputTokens":1,"modelUsage":{\#(models)}\#(incomplete ? #","usageIsIncomplete":true"# : ""),"numTurns":1},"elapsed_ms":900}}}"#
    }

    static func grokModel(_ name: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int = 0, calls: Int, ticks: Int64?) -> String {
        #""\#(name)":{"inputTokens":\#(input),"outputTokens":\#(output),"totalTokens":\#(input + output),"cachedReadTokens":\#(cacheRead),"cacheCreationTokens":\#(cacheWrite),"reasoningTokens":5,"modelCalls":\#(calls)\#(ticks.map { #","costUsdTicks":\#($0)"# } ?? "")}"#
    }

    static func grokChunk(_ date: Date) -> String {
        #"{"timestamp":\#(Int(date.timeIntervalSince1970)),"method":"session/update","params":{"sessionId":"g1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"turn_completed"}}}}"#
    }

    static func clineRequest(_ date: Date, tokensIn: Int, tokensOut: Int, cacheReads: Int, cacheWrites: Int, cost: Double, model: String? = "claude-sonnet-5") -> String {
        let text = #"{\"request\":\"<task>secret prompt</task>\",\"tokensIn\":\#(tokensIn),\"tokensOut\":\#(tokensOut),\"cacheWrites\":\#(cacheWrites),\"cacheReads\":\#(cacheReads),\"cost\":\#(cost)}"#
        let info = model.map { #","modelInfo":{"providerId":"anthropic","modelId":"\#($0)","mode":"act"}"# } ?? ""
        return #"{"ts":\#(Int64(date.timeIntervalSince1970 * 1000)),"type":"say","say":"api_req_started","text":"\#(text)"\#(info)}"#
    }

    static func clineReply(_ date: Date) -> String {
        #"{"ts":\#(Int64(date.timeIntervalSince1970 * 1000)),"type":"say","say":"text","text":"{\"tokensIn\":999}","modelInfo":{"providerId":"anthropic","modelId":"claude-sonnet-5","mode":"act"}}"#
    }
}

struct QwenCodeSessionReaderTests {
    private let noon = TestDates.noon
    private var period: ActivityPeriod { ActivityPeriod(now: noon, calendar: TestDates.utc) }

    @Test func readsTodaysAnswersAndSplitsTheCache() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("projects/-Users-me-app/chats/s1.jsonl", lines: [
            NewProviderFixture.qwenPrompt(noon.addingTimeInterval(-700)),
            NewProviderFixture.qwenAnswer(noon.addingTimeInterval(-600), uuid: "a1", prompt: 1_000, cached: 800, output: 50, thoughts: 10),
            NewProviderFixture.qwenAnswer(noon.addingTimeInterval(-86_400), uuid: "a0", prompt: 500, cached: 0, output: 20),
        ], modified: noon)
        // Workflow journals in the same tree aren't answers.
        try dir.writeJSONL("projects/-Users-me-app/workflows/runs/r1/journal.jsonl", lines: [
            NewProviderFixture.qwenAnswer(noon, uuid: "w1", prompt: 9_000, cached: 0, output: 9),
        ], modified: noon)

        let result = await QwenCodeSessionReader().activity(root: dir.url.appending(path: "projects"), period: period)
        #expect(result.activity.requests == 1)
        #expect(result.activity.tokens == 1_060)
        #expect(result.activity.models.first?.modelID == "qwen3-coder-plus")
        #expect(result.activity.models.first?.inputTokens == 1_000)
        #expect(result.activity.models.first?.outputTokens == 60)
        #expect(result.history.days.suffix(2).map(\.tokens) == [520, 1_060])
    }

    /// A resumed session copies earlier records with their identifiers.
    @Test func countsAnAnswerOnce() async throws {
        let dir = try TemporaryDirectory()
        let answer = NewProviderFixture.qwenAnswer(noon, uuid: "a1", prompt: 100, cached: 0, output: 10)
        try dir.writeJSONL("projects/a/chats/s1.jsonl", lines: [answer], modified: noon)
        try dir.writeJSONL("projects/a/chats/s2.jsonl", lines: [answer], modified: noon)

        let result = await QwenCodeSessionReader().activity(root: dir.url.appending(path: "projects"), period: period)
        #expect(result.activity.requests == 1)
        #expect(result.activity.tokens == 110)
    }
}

struct GrokBuildSessionReaderTests {
    private let noon = TestDates.noon
    private var period: ActivityPeriod { ActivityPeriod(now: noon, calendar: TestDates.utc) }

    @Test func readsCompletedTurnsPerModelWithXAIsCost() async throws {
        let dir = try TemporaryDirectory()
        let models = [
            NewProviderFixture.grokModel("grok-build", input: 10_000, output: 400, cacheRead: 8_000, calls: 3, ticks: 120_000_000),
            NewProviderFixture.grokModel("grok-code-fast-1", input: 2_000, output: 100, cacheRead: 0, cacheWrite: 500, calls: 1, ticks: 30_000_000),
        ].joined(separator: ",")
        try dir.writeJSONL("sessions/%2FUsers%2Fme%2Fapp/g1/updates.jsonl", lines: [
            NewProviderFixture.grokChunk(noon.addingTimeInterval(-700)),
            NewProviderFixture.grokTurn(noon.addingTimeInterval(-600), prompt: "p1", models: models),
        ], modified: noon)
        // Other logs in a session folder aren't read.
        try dir.writeJSONL("sessions/%2FUsers%2Fme%2Fapp/g1/chat_history.jsonl", lines: [
            NewProviderFixture.grokTurn(noon, prompt: "p9", models: NewProviderFixture.grokModel("grok-build", input: 99_999, output: 1, cacheRead: 0, calls: 1, ticks: nil)),
        ], modified: noon)

        let result = await GrokBuildSessionReader().activity(root: dir.url.appending(path: "sessions"), period: period)
        #expect(result.activity.tokens == 12_500)
        #expect(result.activity.requests == 4, "Model calls, not turns")
        #expect(result.activity.estimatedCost == Decimal(string: "0.015"))
        #expect(result.activity.isCostComplete)
        let build = result.activity.models.first { $0.modelID == "grok-build" }
        #expect(build?.requests == 3)
        #expect(build?.estimatedCost == Decimal(string: "0.012"))
    }

    /// xAI's cost isn't trusted for a turn whose usage is incomplete.
    @Test func dropsTheCostOfAnIncompleteTurn() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("sessions/w/g1/updates.jsonl", lines: [
            NewProviderFixture.grokTurn(noon, prompt: "p1", models: NewProviderFixture.grokModel("grok-build", input: 100, output: 10, cacheRead: 0, calls: 1, ticks: 50_000_000), incomplete: true),
        ], modified: noon)

        let result = await GrokBuildSessionReader().activity(root: dir.url.appending(path: "sessions"), period: period)
        #expect(result.activity.tokens == 110)
        #expect(result.activity.estimatedCost == nil)
        #expect(!result.activity.isCostComplete)
    }
}

struct ClineActivityReaderTests {
    private let noon = TestDates.noon
    private var period: ActivityPeriod { ActivityPeriod(now: noon, calendar: TestDates.utc) }

    private func environment(_ dir: TemporaryDirectory) -> ClineEnvironment {
        ClineEnvironment(
            extensionTaskRoots: [dir.url.appending(path: "Code/User/globalStorage/saoudrizwan.claude-dev/tasks")],
            cliData: dir.url.appending(path: "cline-data"),
            executable: nil
        )
    }

    private func writeTask(_ dir: TemporaryDirectory, id: String, messages: [String], modified: Date) throws {
        let path = "Code/User/globalStorage/saoudrizwan.claude-dev/tasks/\(id)/ui_messages.json"
        try dir.write(path, text: "[" + messages.joined(separator: ",") + "]")
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: dir.url.appending(path: path).path)
    }

    @Test func readsEditorTasksWithClinesOwnCost() async throws {
        let dir = try TemporaryDirectory()
        try writeTask(dir, id: "1789127000000", messages: [
            NewProviderFixture.clineReply(noon.addingTimeInterval(-800)),
            NewProviderFixture.clineRequest(noon.addingTimeInterval(-700), tokensIn: 300, tokensOut: 50, cacheReads: 1_000, cacheWrites: 200, cost: 0.0125),
            NewProviderFixture.clineRequest(noon.addingTimeInterval(-600), tokensIn: 100, tokensOut: 20, cacheReads: 0, cacheWrites: 0, cost: 0.002),
            // Still running: no counts yet.
            NewProviderFixture.clineRequest(noon.addingTimeInterval(-500), tokensIn: 0, tokensOut: 0, cacheReads: 0, cacheWrites: 0, cost: 0),
        ], modified: noon)

        let result = await ClineActivityReader().activity(environment: environment(dir), period: period)
        #expect(result.activity.requests == 2)
        #expect(result.activity.tokens == 1_670)
        #expect(result.activity.estimatedCost == Decimal(string: "0.0145"))
        #expect(result.activity.models.map(\.modelID) == ["claude-sonnet-5"])
        #expect(result.hasTasks)
    }

    @Test func readsCLISessions() async throws {
        let dir = try TemporaryDirectory()
        let file = """
        {"sessionId":"cli-1","agent":"lead","messages":[
          {"role":"user","ts":\(Int64(noon.addingTimeInterval(-60).timeIntervalSince1970 * 1000)),"content":[{"type":"text","text":"secret"}]},
          {"id":"m1","role":"assistant","ts":\(Int64(noon.addingTimeInterval(-30).timeIntervalSince1970 * 1000)),"modelInfo":{"id":"cline-pass/glm-5.2","provider":"cline-pass"},"content":[{"type":"text","text":"reply"}],"metrics":{"inputTokens":700,"outputTokens":30,"cacheReadTokens":50,"cacheWriteTokens":0,"cost":0.011}},
          {"role":"assistant","metrics":{"inputTokens":0,"outputTokens":0}}
        ]}
        """
        try dir.write("cline-data/sessions/cli-1/cli-1.messages.json", text: file)
        try FileManager.default.setAttributes([.modificationDate: noon], ofItemAtPath: dir.url.appending(path: "cline-data/sessions/cli-1/cli-1.messages.json").path)

        let result = await ClineActivityReader().activity(environment: environment(dir), period: period)
        #expect(result.activity.requests == 1)
        #expect(result.activity.tokens == 780)
        #expect(result.activity.estimatedCost == Decimal(string: "0.011"))
        #expect(result.activity.models.map(\.modelID) == ["cline-pass/glm-5.2"])
    }

    /// A task rewritten with more requests is read again; an unchanged one isn't.
    @Test func rereadsATaskOnlyWhenItChanges() async throws {
        let dir = try TemporaryDirectory()
        let reader = ClineActivityReader()
        let first = NewProviderFixture.clineRequest(noon.addingTimeInterval(-700), tokensIn: 100, tokensOut: 10, cacheReads: 0, cacheWrites: 0, cost: 0.001)
        try writeTask(dir, id: "t1", messages: [first], modified: noon.addingTimeInterval(-600))
        #expect(await reader.activity(environment: environment(dir), period: period).activity.requests == 1)

        let second = NewProviderFixture.clineRequest(noon.addingTimeInterval(-60), tokensIn: 50, tokensOut: 5, cacheReads: 0, cacheWrites: 0, cost: 0.0005)
        try writeTask(dir, id: "t1", messages: [first, second], modified: noon)
        let result = await reader.activity(environment: environment(dir), period: period)
        #expect(result.activity.requests == 2)
        #expect(result.activity.tokens == 165)
    }
}

struct RecordedCostTests {
    private let noon = TestDates.noon

    /// A cost the tool recorded is used as is; without one, the price table
    /// estimates; a model with neither leaves the total partial.
    @Test func mixesRecordedCostsAndEstimates() {
        let prices = ModelPriceTable(generated: nil, prices: ["priced-model": ModelPrice(input: 1, output: 2)])
        let records = [
            ActivityRecord(key: "a", timestamp: noon, tokens: 100, model: "tool-model", breakdown: TokenBreakdown(input: 100), requests: 3, cost: Decimal(string: "0.5")),
            ActivityRecord(key: "b", timestamp: noon, tokens: 1_000_000, model: "priced-model", breakdown: TokenBreakdown(input: 1_000_000)),
            ActivityRecord(key: "c", timestamp: noon, tokens: 10, model: "unpriced-model", breakdown: TokenBreakdown(input: 10)),
        ]
        let summary = ActivitySummary(records: records, since: noon.addingTimeInterval(-60), prices: prices)
        #expect(summary.requests == 5)
        #expect(summary.estimatedCost == Decimal(string: "1.5"))
        #expect(!summary.isCostComplete)
        #expect(summary.models.first { $0.modelID == "tool-model" }?.requests == 3)
    }
}
