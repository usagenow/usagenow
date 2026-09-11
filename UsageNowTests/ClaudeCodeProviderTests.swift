import Foundation
import Testing
@testable import UsageNow

struct ClaudeCodeProviderTests {
    private let noon = TestDates.noon

    private func environment(_ dir: TemporaryDirectory, profile: String? = ClaudeProfileFixture.pro) throws -> ClaudeCodeEnvironment {
        let config = dir.url.appending(path: ".claude.json")
        if let profile { try dir.write(".claude.json", text: profile) }
        return ClaudeCodeEnvironment(
            configDirectory: dir.url.appending(path: ".claude"),
            globalConfigFile: config,
            configDirectoryExists: true,
            configDirectoryIsReadable: true,
            globalConfigExists: profile != nil,
            hasExecutable: false
        )
    }

    private func provider(
        _ environment: ClaudeCodeEnvironment,
        client: ClaudeUsageLimitsClient? = nil,
        limitsEnabled: Bool = false,
        now: Date? = nil
    ) -> ClaudeCodeProvider {
        let date = now ?? noon
        return ClaudeCodeProvider(
            discover: { environment },
            limitsClient: client,
            limitsEnabled: FeatureSwitch(limitsEnabled),
            now: { date },
            calendar: TestDates.utc
        )
    }

    // MARK: Discovery and profile

    @Test func notInstalled() async throws {
        let environment = ClaudeCodeEnvironment(
            configDirectory: URL(filePath: "/nonexistent/.claude"),
            globalConfigFile: URL(filePath: "/nonexistent/.claude.json"),
            configDirectoryExists: false,
            configDirectoryIsReadable: false,
            globalConfigExists: false,
            hasExecutable: false
        )
        #expect(try await provider(environment).fetchSnapshot(trigger: .automatic).status == .notInstalled)
    }

    @Test func discoversCustomConfigDirectory() throws {
        let dir = try TemporaryDirectory()
        try dir.write("custom/.claude.json", text: ClaudeProfileFixture.pro)
        let environment = ClaudeCodeEnvironment.discover(environment: ["CLAUDE_CONFIG_DIR": dir.url.appending(path: "custom").path], homeDirectory: dir.url)
        #expect(environment.configDirectoryExists)
        #expect(environment.globalConfigExists)
        #expect(environment.sessionRoots.first?.lastPathComponent == "projects")
    }

    @Test func signedOutWithoutProfileOrSessions() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, profile: #"{"projects":{}}"#)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notAuthenticated)
    }

    @Test func readsPlanFromCachedProfile() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.planName == "Pro")
        #expect(snapshot.windows.isEmpty)
        #expect(!snapshot.capabilities.contains(.quota))
    }

    @Test(arguments: zip(
        ["claude_pro", "claude_max", "claude_max", "claude_team", "claude_enterprise", "claude_free", "something_new"] as [String?],
        [nil, "default_claude_max_20x", nil, nil, nil, nil, nil] as [String?]
    ))
    func planMapping(organizationType: String?, tier: String?) {
        let name = ClaudePlan.displayName(organizationType: organizationType, rateLimitTier: tier)
        switch organizationType {
        case "claude_pro": #expect(name == "Pro")
        case "claude_max": #expect(name == (tier == nil ? "Max" : "Max 20x"))
        case "claude_team": #expect(name == "Team")
        case "claude_enterprise": #expect(name == "Enterprise")
        default: #expect(name == nil)
        }
    }

    @Test func unknownOrganizationTypeHidesBadge() async throws {
        let dir = try TemporaryDirectory()
        let profile = #"{"oauthAccount":{"organizationType":"claude_something_else"}}"#
        let snapshot = try await provider(environment(dir, profile: profile)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.planName == nil)
    }

    // MARK: Local activity

    @Test func deduplicatesStreamingRecords() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir)
        try dir.writeJSONL(".claude/projects/example-project/session-a.jsonl", lines: [
            ClaudeFixture.user(noon.addingTimeInterval(-120)),
            // One response streamed as three content blocks with identical usage.
            ClaudeFixture.assistant(noon.addingTimeInterval(-100), messageID: "msg-1", requestID: "req-1"),
            ClaudeFixture.assistant(noon.addingTimeInterval(-99), messageID: "msg-1", requestID: "req-1"),
            ClaudeFixture.assistant(noon.addingTimeInterval(-98), messageID: "msg-1", requestID: "req-1"),
            ClaudeFixture.assistant(noon.addingTimeInterval(-50), messageID: "msg-2", requestID: "req-2", model: "claude-example-2", output: 400),
        ], modified: noon)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 2)
        #expect(snapshot.activity.tokensToday == 560) // 100 + 460
        #expect(snapshot.recentModel == "claude-example-2")
    }

    @Test func countsSubagentSessionsAndSkipsSyntheticMessages() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir)
        try dir.writeJSONL(".claude/projects/example-project/session-a.jsonl", lines: [
            ClaudeFixture.assistant(noon.addingTimeInterval(-60), messageID: "msg-1", requestID: "req-1"),
            ClaudeFixture.assistant(noon.addingTimeInterval(-30), messageID: "msg-err", requestID: "req-err", model: "<synthetic>"),
        ], modified: noon)
        try dir.writeJSONL(".claude/projects/example-project/session-a/subagents/agent-1.jsonl", lines: [
            ClaudeFixture.assistant(noon.addingTimeInterval(-40), messageID: "msg-sub", requestID: "req-sub", sidechain: true),
        ], modified: noon)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 2)
        #expect(snapshot.recentModel == "claude-example-1")
    }

    @Test func respectsDayBoundaryAndMalformedLines() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir)
        let midnight = TestDates.utc.startOfDay(for: noon)
        try dir.writeJSONL(".claude/projects/p/session.jsonl", lines: [
            ClaudeFixture.assistant(midnight.addingTimeInterval(-1), messageID: "old", requestID: "old"),
            "{ broken json",
            #"{"type":"assistant","timestamp":"2026-09-11T10:00:00Z","message":{"usage":{"input_tokens":"many"}}}"#,
            ClaudeFixture.assistant(midnight.addingTimeInterval(5), messageID: "new", requestID: "new"),
        ], modified: noon)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 1)
        #expect(snapshot.activity.tokensToday == 100)
    }

    @Test func noSessionsTodayMeansZeroActivity() async throws {
        let dir = try TemporaryDirectory()
        let environment = try environment(dir)
        try dir.writeJSONL(".claude/projects/p/old.jsonl", lines: [
            ClaudeFixture.assistant(noon.addingTimeInterval(-2 * 86_400), messageID: "m", requestID: "r"),
        ], modified: noon.addingTimeInterval(-2 * 86_400))

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity == LocalActivity(tokensToday: 0, requestsToday: 0))
        #expect(snapshot.recentModel == nil)
    }

    // MARK: Experimental usage limits

    @Test func disabledLimitsNeverTouchKeychainOrNetwork() async throws {
        let dir = try TemporaryDirectory()
        let credentials = StubCredentials(token: "fake-token")
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let client = ClaudeUsageLimitsClient(credentials: credentials, transport: transport)

        let snapshot = try await provider(environment(dir), client: client, limitsEnabled: false).fetchSnapshot(trigger: .manual)
        #expect(snapshot.windows.isEmpty)
        #expect(await credentials.reads == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test func enabledLimitsProduceWindows() async throws {
        let dir = try TemporaryDirectory()
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: transport)

        let snapshot = try await provider(environment(dir), client: client, limitsEnabled: true).fetchSnapshot(trigger: .automatic)

        #expect(await client.availability == .available)
        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly, .weekly])
        #expect(snapshot.window(.fiveHour)?.usage?.displayValue == 37)
        #expect(snapshot.windows.last?.scope == "Opus")
        #expect(snapshot.limitsUpdatedAt != nil)

        let request = try #require(await transport.requests.first)
        #expect(request.url == ClaudeUsageLimitsClient.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-token")
    }

    @Test func rejectedTokenIsReReadOnlyOnManualRefresh() async throws {
        let credentials = StubCredentials(token: "fake-token")
        let transport = StubTransport(status: 401, body: "{}")
        let client = ClaudeUsageLimitsClient(credentials: credentials, transport: transport, minimumInterval: 0)
        let now: @Sendable () -> Date = { TestDates.noon }

        #expect(await client.windows(trigger: .automatic, now: now) == nil)
        #expect(await client.availability == .staleAuthentication)
        #expect(await client.windows(trigger: .automatic, now: now) == nil)
        #expect(await credentials.reads == 1)

        #expect(await client.windows(trigger: .manual, now: now) == nil)
        #expect(await credentials.reads == 2)
    }

    @Test func deniedKeychainAccessIsNotAskedAgainAutomatically() async throws {
        let credentials = StubCredentials(token: nil, denied: true)
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let client = ClaudeUsageLimitsClient(credentials: credentials, transport: transport, minimumInterval: 0)
        let now: @Sendable () -> Date = { TestDates.noon }

        _ = await client.windows(trigger: .automatic, now: now)
        _ = await client.windows(trigger: .automatic, now: now)
        #expect(await credentials.reads == 1)
        #expect(await client.availability == .keychainDenied)
        #expect(await transport.requests.isEmpty)

        _ = await client.windows(trigger: .manual, now: now)
        #expect(await credentials.reads == 2)

        await client.reset()
        #expect(await client.availability == .disabled)
    }

    @Test func availabilityMapsToShortUserFacingReasons() {
        #expect(ClaudeQuotaAvailability.available.unavailableReason == nil)
        #expect(ClaudeQuotaAvailability.disabled.unavailableReason == nil)
        #expect(ClaudeQuotaAvailability.staleAuthentication.unavailableReason == .signInExpired)
        #expect(ClaudeQuotaAvailability.keychainDenied.unavailableReason == .permissionDenied)
        #expect(ClaudeQuotaAvailability.endpointUnavailable.unavailableReason == .temporarilyUnavailable)
        #expect(ClaudeQuotaAvailability.unsupportedResponse.unavailableReason == .temporarilyUnavailable)
    }

    @Test func snapshotCarriesTheReasonWhenLimitsAreOn() async throws {
        let dir = try TemporaryDirectory()
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: nil, denied: true), transport: StubTransport(status: 200, body: "{}"))
        let snapshot = try await provider(environment(dir), client: client, limitsEnabled: true).fetchSnapshot(trigger: .manual)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.quotaUnavailableReason == .permissionDenied)
    }

    @Test func noReasonWhileTheExperimentalSettingIsOff() async throws {
        let dir = try TemporaryDirectory()
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: nil, denied: true), transport: StubTransport(status: 200, body: "{}"))
        let snapshot = try await provider(environment(dir), client: client, limitsEnabled: false).fetchSnapshot(trigger: .manual)
        #expect(snapshot.quotaUnavailableReason == nil)
    }

    @Test func unsupportedResponseIsReportedAsTemporarilyUnavailable() async throws {
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: StubTransport(status: 200, body: "[1,2]"))
        #expect(await client.windows(trigger: .manual, now: { TestDates.noon }) == nil)
        #expect(await client.availability == .unsupportedResponse)
    }

    @Test func serverErrorIsReportedAsEndpointUnavailable() async throws {
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: StubTransport(status: 503, body: ""))
        #expect(await client.windows(trigger: .manual, now: { TestDates.noon }) == nil)
        #expect(await client.availability == .endpointUnavailable)
    }

    @Test func missingSignInReportsStatus() async throws {
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: nil), transport: StubTransport(status: 200, body: "{}"))
        #expect(await client.windows(trigger: .manual, now: { TestDates.noon }) == nil)
        #expect(await client.availability == .staleAuthentication)
    }

    @Test func automaticRefreshesReuseCacheForFiveMinutes() async throws {
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: transport)
        let clock = TestClock(TestDates.noon)
        let now: @Sendable () -> Date = { clock.now }

        _ = await client.windows(trigger: .automatic, now: now)
        clock.advance(by: 4 * 60)
        _ = await client.windows(trigger: .automatic, now: now)
        #expect(await transport.requests.count == 1)

        clock.advance(by: 60)
        _ = await client.windows(trigger: .automatic, now: now)
        #expect(await transport.requests.count == 2)

        _ = await client.windows(trigger: .manual, now: now)
        #expect(await transport.requests.count == 3)
    }

    @Test func concurrentCallsShareOneRequest() async throws {
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full, delay: .milliseconds(50))
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: transport)
        let now: @Sendable () -> Date = { TestDates.noon }

        async let a = client.windows(trigger: .manual, now: now)
        async let b = client.windows(trigger: .manual, now: now)
        async let c = client.windows(trigger: .manual, now: now)
        _ = await (a, b, c)
        #expect(await transport.requests.count == 1)
    }

    @Test func transientFailureKeepsLastLimits() async throws {
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let client = ClaudeUsageLimitsClient(credentials: StubCredentials(token: "fake-token"), transport: transport)
        let now: @Sendable () -> Date = { TestDates.noon }

        #expect(await client.windows(trigger: .manual, now: now)?.value.count == 3)
        await transport.setStatus(500)
        #expect(await client.windows(trigger: .manual, now: now)?.value.count == 3)
    }

    @Test func expiredTokenIsNotSent() async throws {
        let transport = StubTransport(status: 200, body: ClaudeUsageFixture.full)
        let credentials = StubCredentials(token: "fake-token", expiresAt: TestDates.noon.addingTimeInterval(-60))
        let client = ClaudeUsageLimitsClient(credentials: credentials, transport: transport)

        #expect(await client.windows(trigger: .manual, now: { TestDates.noon }) == nil)
        #expect(await transport.requests.isEmpty)
        #expect(await client.availability == .staleAuthentication)

        // Automatic refreshes don't read the keychain again until a manual refresh.
        _ = await client.windows(trigger: .automatic, now: { TestDates.noon.addingTimeInterval(600) })
        #expect(await credentials.reads == 1)
    }

    @Test func tokenIsRedactedInDescriptions() {
        let token = ClaudeOAuthToken(value: "fake-secret", expiresAt: nil)
        #expect(!"\(token)".contains("fake-secret"))
        #expect(!String(reflecting: token).contains("fake-secret"))
    }

    // MARK: Response parsing

    @Test func parsesWindowsDefensively() throws {
        let windows = try #require(ClaudeUsageLimitsParser.windows(from: Data(ClaudeUsageFixture.full.utf8)))
        #expect(windows.count == 3)
        #expect(windows[0].kind == .fiveHour)
        #expect(abs((windows[0].resetsAt?.timeIntervalSince1970 ?? 0) - 1_789_138_800.123456) < 0.001)
        #expect(windows[1].kind == .weekly && windows[1].scope == nil)
        #expect(windows[2].kind == .weekly && windows[2].scope == "Opus")
    }

    @Test(arguments: [
        ("five_hour", UsageWindowKind.fiveHour, nil),
        ("seven_day", .weekly, nil),
        ("seven_day_sonnet", .weekly, "Sonnet"),
        ("thirty_day", .custom(minutes: 43_200), nil),
    ] as [(String, UsageWindowKind, String?)])
    func windowKeys(key: String, kind: UsageWindowKind, scope: String?) throws {
        let parsed = try #require(ClaudeUsageLimitsParser.window(forKey: key))
        #expect(parsed.0 == kind)
        #expect(parsed.1 == scope)
    }

    @Test(arguments: ["extra_usage", "seven_day_oauth_apps", "weekly", "five", ""])
    func unknownWindowKeysAreSkipped(key: String) {
        #expect(ClaudeUsageLimitsParser.window(forKey: key) == nil)
    }

    @Test func nonObjectResponseIsRejected() {
        #expect(ClaudeUsageLimitsParser.windows(from: Data("[1,2]".utf8)) == nil)
        #expect(ClaudeUsageLimitsParser.windows(from: Data("not json".utf8)) == nil)
    }

    @Test func parsesCredentialWithoutKeepingOtherFields() {
        let json = #"{"claudeAiOauth":{"accessToken":"fake-access","refreshToken":"fake-refresh","expiresAt":1789138800000,"scopes":["user:inference"]}}"#
        let token = ClaudeCredentialParser.token(from: Data(json.utf8))
        #expect(token?.value == "fake-access")
        #expect(token?.expiresAt == Date(timeIntervalSince1970: 1_789_138_800))
        #expect(ClaudeCredentialParser.token(from: Data(#"{"other":{}}"#.utf8)) == nil)
    }
}

enum ClaudeProfileFixture {
    static let pro = #"{"projects":{"/tmp/example":{}},"oauthAccount":{"organizationType":"claude_pro","organizationRateLimitTier":"default_claude_ai","emailAddress":"person@example.com"}}"#
}

enum ClaudeUsageFixture {
    static let full = #"""
    {
      "five_hour": {"utilization": 37.0, "resets_at": "2026-09-11T15:00:00.123456+00:00"},
      "seven_day": {"utilization": 12, "resets_at": "2026-09-15T09:00:00+00:00"},
      "seven_day_opus": {"utilization": 3.5, "resets_at": null},
      "seven_day_sonnet": null,
      "seven_day_oauth_apps": {"utilization": 1},
      "extra_usage": {"is_enabled": false, "monthly_limit": null},
      "brand_new_bucket": {"utilization": 50}
    }
    """#
}

actor StubCredentials: ClaudeCredentialSource {
    private let token: String?
    private let expiresAt: Date?
    private let denied: Bool
    private(set) var reads = 0

    init(token: String?, expiresAt: Date? = nil, denied: Bool = false) {
        self.token = token
        self.expiresAt = expiresAt
        self.denied = denied
    }

    func lookup() async throws -> ClaudeCredentialLookup {
        reads += 1
        if denied { return .accessDenied }
        guard let token else { return .notFound }
        return .found(ClaudeOAuthToken(value: token, expiresAt: expiresAt))
    }
}

actor StubTransport: HTTPTransport {
    private var status: Int
    private let body: String
    private let delay: Duration
    private(set) var requests: [URLRequest] = []

    init(status: Int, body: String, delay: Duration = .zero) {
        self.status = status
        self.body = body
        self.delay = delay
    }

    func setStatus(_ status: Int) {
        self.status = status
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if delay > .zero { try await Task.sleep(for: delay) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
