import Foundation
import Testing
@testable import UsageNow

/// Claude model analytics and Team plans, through the real provider.
///
/// Team behavior is written against the fields Claude Code caches
/// (`organizationType`, `seatTier`) and the usage endpoint's documented
/// shape; it has not been checked against a live Team account.
struct ClaudeModelsAndTeamTests {
    private let noon = TestDates.noon

    private func environment(_ dir: TemporaryDirectory, profile: String) throws -> ClaudeCodeEnvironment {
        try dir.write(".claude.json", text: profile)
        return ClaudeCodeEnvironment(
            configDirectory: dir.url.appending(path: ".claude"),
            globalConfigFile: dir.url.appending(path: ".claude.json"),
            configDirectoryExists: true,
            configDirectoryIsReadable: true,
            globalConfigExists: true,
            executable: nil
        )
    }

    private func provider(_ environment: ClaudeCodeEnvironment, client: ClaudeUsageLimitsClient? = nil) -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            discover: { environment },
            limitsClient: client,
            limitsEnabled: FeatureSwitch(client != nil),
            now: { TestDates.noon },
            calendar: TestDates.utc
        )
    }

    private static func profile(_ organizationType: String, seatTier: String? = nil) -> String {
        let seat = seatTier.map { #""\#($0)""# } ?? "null"
        return #"{"oauthAccount":{"organizationType":"\#(organizationType)","seatTier":\#(seat),"organizationRole":"member","organizationName":"Example Org","emailAddress":"person@example.com","organizationUuid":"00000000-0000-0000-0000-000000000000"}}"#
    }

    // MARK: Models today

    @Test func sessionsProduceModelActivity() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir, profile: Self.profile("claude_max"))
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            ClaudeFixture.assistant(noon.addingTimeInterval(-300), messageID: "m1", requestID: "r1", model: "claude-fable-5-1", input: 1_000, cacheCreation: 0, cacheRead: 5_000, output: 400),
            ClaudeFixture.assistant(noon.addingTimeInterval(-299), messageID: "m1", requestID: "r1", model: "claude-fable-5-1", input: 1_000, cacheCreation: 0, cacheRead: 5_000, output: 400),
            ClaudeFixture.assistant(noon.addingTimeInterval(-200), messageID: "m2", requestID: "r2", model: "claude-opus-5", input: 10, cacheCreation: 0, cacheRead: 0, output: 90),
            ClaudeFixture.assistant(noon.addingTimeInterval(-100), messageID: "m3", requestID: "r3", model: "claude-fable-5-1", input: 50, cacheCreation: 50, cacheRead: 0, output: 100),
        ], modified: noon)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)

        #expect(snapshot.modelActivity.map(\.displayName) == ["Fable 5.1", "Opus 5"])
        let fable = try #require(snapshot.modelActivity.first)
        #expect(fable.requests == 2, "Streamed copies of a response count once")
        #expect(fable.totalTokens == 6_600)
        #expect(fable.inputTokens == 6_100)
        #expect(fable.outputTokens == 500)
        #expect(snapshot.activity.tokensToday == 6_700)
        #expect(snapshot.recentModel == "claude-fable-5-1")
    }

    @Test func malformedAndModelessLinesDontBreakModelActivity() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir, profile: Self.profile("claude_pro"))
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            "{ not json",
            #"{"type":"assistant","timestamp":"\#(TestDates.iso(noon.addingTimeInterval(-90)))","requestId":"r0","message":{"id":"m0","usage":{"input_tokens":5,"output_tokens":5}}}"#,
            #"{"type":"assistant","timestamp":"\#(TestDates.iso(noon.addingTimeInterval(-80)))","message":{"model":"claude-opus-5","usage":{"input_tokens":"lots"}}}"#,
            ClaudeFixture.assistant(noon.addingTimeInterval(-60), messageID: "m1", requestID: "r1", model: "claude-opus-5"),
        ], modified: noon)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 2)
        #expect(snapshot.modelActivity.map(\.modelID) == ["claude-opus-5"])
    }

    @Test func noSessionsMeansNoModelRows() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, profile: Self.profile("claude_pro"))).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.modelActivity.isEmpty)
    }

    // MARK: Plans

    @Test(arguments: [
        ("claude_pro", nil, "Pro"),
        ("claude_max", nil, "Max"),
        ("claude_team", nil, "Team"),
        ("claude_team", "premium", "Team · Premium"),
        ("claude_team", "standard", "Team · Standard"),
        ("claude_team", "team_premium", "Team · Premium"),
        ("claude_team", "something_new", "Team"),
        ("claude_enterprise", "premium", "Enterprise · Premium"),
        ("claude_pro", "premium", "Pro"),
    ] as [(String, String?, String)])
    func planNames(organizationType: String, seatTier: String?, expected: String) async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, profile: Self.profile(organizationType, seatTier: seatTier))).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.planName == expected)
    }

    @Test func profileReadsOnlyThePlan() throws {
        let dir = try TemporaryDirectory()
        try dir.write(".claude.json", text: Self.profile("claude_team", seatTier: "premium"))
        let profile = ClaudeAccountProfile.read(from: dir.url.appending(path: ".claude.json"))
        // The profile type has no room for names, emails, or organization identifiers.
        #expect(profile == ClaudeAccountProfile(isSignedIn: true, planName: "Team · Premium"))
    }

    // MARK: Team limits

    @Test func teamWithLimitsShowsThemNormally() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir, profile: Self.profile("claude_team", seatTier: "premium"))
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: StubTransport(status: 200, body: ClaudeUsageFixture.full))

        let snapshot = try await provider(environment, client: client).fetchSnapshot(trigger: .manual)
        #expect(snapshot.planName == "Team · Premium")
        #expect(snapshot.window(.fiveHour) != nil)
        #expect(snapshot.quotaUnavailableReason == nil)
    }

    @Test func teamWithoutLimitsIsUnavailableAndKeepsActivity() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir, profile: Self.profile("claude_team", seatTier: "standard"))
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            ClaudeFixture.assistant(noon.addingTimeInterval(-60), messageID: "m1", requestID: "r1", model: "claude-opus-5"),
        ], modified: noon)
        // The endpoint answers, but reports no window with a value.
        let body = #"{"five_hour":null,"seven_day":{"utilization":null,"resets_at":null},"extra_usage":{"is_enabled":false}}"#
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: StubTransport(status: 200, body: body))

        let snapshot = try await provider(environment, client: client).fetchSnapshot(trigger: .manual)
        #expect(snapshot.windows.isEmpty, "Limits are never estimated from activity")
        #expect(snapshot.quotaUnavailableReason == nil)
        #expect(snapshot.activity.requestsToday == 1)
        #expect(snapshot.modelActivity.map(\.modelID) == ["claude-opus-5"])
        #expect(snapshot.planName == "Team · Standard")
    }

    @Test func staleTeamSignInKeepsActivityVisible() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir, profile: Self.profile("claude_team"))
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            ClaudeFixture.assistant(noon.addingTimeInterval(-60), messageID: "m1", requestID: "r1", model: "claude-fable-5-1"),
        ], modified: noon)
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: StubTransport(status: 401, body: "{}"))

        let snapshot = try await provider(environment, client: client).fetchSnapshot(trigger: .manual)
        #expect(snapshot.status == .available)
        #expect(snapshot.quotaUnavailableReason == .signInExpired)
        #expect(snapshot.activity.requestsToday == 1)
        #expect(snapshot.modelActivity.first?.displayName == "Fable 5.1")
    }

    @Test func limitsRequestUsesOnlyTheSignedInUsersEndpoint() async throws {
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: transport)
        _ = await client.windows(trigger: .manual, now: { TestDates.noon })

        let requests = await transport.requests
        #expect(requests.map(\.url) == [ClaudeUsageLimitsClient.endpoint], "No organization or admin endpoints")
        #expect(requests.first?.value(forHTTPHeaderField: "x-api-key") == nil)
    }
}
