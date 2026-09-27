import Foundation
import Testing
@testable import UsageNow

struct CodexProviderTests {
    private let noon = TestDates.noon
    private var yesterday: Date { noon.addingTimeInterval(-24 * 3600) }

    private func environment(_ dir: TemporaryDirectory, executable: Bool = true, authFile: Bool = true) -> CodexEnvironment {
        CodexEnvironment(
            home: dir.url,
            executable: executable ? URL(filePath: "/nonexistent/codex") : nil,
            homeExists: true,
            homeIsReadable: true,
            hasAuthFile: authFile
        )
    }

    private func provider(
        _ environment: CodexEnvironment,
        now: Date? = nil,
        appServer: CodexProvider.AppServerFetch? = nil
    ) -> CodexProvider {
        let date = now ?? noon
        return CodexProvider(discover: { environment }, appServer: appServer, now: { date }, calendar: TestDates.utc)
    }

    // MARK: Discovery

    @Test func notInstalledWithoutHomeOrExecutable() async throws {
        let environment = CodexEnvironment(home: URL(filePath: "/nonexistent"), executable: nil, homeExists: false, homeIsReadable: false, hasAuthFile: false)
        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notInstalled)
    }

    @Test func unreadableHomeIsUnavailable() async throws {
        let environment = CodexEnvironment(home: URL(filePath: "/nonexistent"), executable: nil, homeExists: true, homeIsReadable: false, hasAuthFile: false)
        #expect(try await provider(environment).fetchSnapshot(trigger: .automatic).status == .unavailable)
    }

    @Test func discoversHomeFromEnvironment() throws {
        let dir = try TemporaryDirectory()
        try dir.write("auth.json", text: "{}")
        let environment = CodexEnvironment.discover(environment: ["CODEX_HOME": dir.url.path], homeDirectory: dir.url)
        #expect(environment.homeExists)
        #expect(environment.hasAuthFile)
        #expect(environment.sessionRoots.first?.lastPathComponent == "sessions")
    }

    /// ChatGPT 26.9 moved its bundled CLI into Resources/codex-cli/bin.
    /// Both layouts are searched, the app's own copy before any other.
    @Test func findsTheCLIBundledWithTheApp() throws {
        let dir = try TemporaryDirectory()
        let candidates = CodexEnvironment.executableCandidates(homeDirectory: dir.url).map(\.path)
        let old = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let moved = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        #expect(candidates.contains(old))
        #expect(candidates.contains(moved))
        let homebrew = try #require(candidates.firstIndex(of: "/opt/homebrew/bin/codex"))
        #expect(try #require(candidates.firstIndex(of: moved)) < homebrew)
    }

    /// People who use Codex only in an editor have its CLI inside the
    /// extension. It's the last resort, newest version first.
    @Test func findsTheCLIBundledWithAnEditorExtension() throws {
        let dir = try TemporaryDirectory()
        for version in ["26.9.1", "26.10.0"] {
            try dir.write(".vscode/extensions/openai.chatgpt-\(version)-darwin-arm64/bin/macos-aarch64/codex", text: "")
        }
        try dir.write(".vscode/extensions/someone.else-1.0.0/bin/macos-aarch64/codex", text: "")

        let found = CodexEnvironment.editorExtensionCandidates(homeDirectory: dir.url).map { $0.pathComponents.suffix(4).joined(separator: "/") }
        #expect(found.count == 2)
        #expect(found.first?.hasPrefix("openai.chatgpt-26.10.0") == true)
        let all = CodexEnvironment.executableCandidates(homeDirectory: dir.url)
        #expect(all.last?.path.contains("openai.chatgpt-26.9.1") == true)
    }

    @Test func missingSessionDirectoriesMeanNoActivity() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.activity.tokensToday == 0)
        #expect(snapshot.activity.requestsToday == 0)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.planName == nil)
    }

    @Test func signedOutAccordingToAppServer() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir), appServer: { _ in .notSignedIn }).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notAuthenticated)
    }

    // MARK: Local activity

    @Test func aggregatesTodaysUsageRecords() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("sessions/2026/09/10/rollout-a.jsonl", lines: [
            CodexFixture.usageRecord(yesterday, responseID: "r-old", total: 9_000),
            CodexFixture.turnContext(noon.addingTimeInterval(-3600), model: "gpt-example-1"),
            CodexFixture.usageRecord(noon.addingTimeInterval(-3000), responseID: "r-1", total: 1_000),
            CodexFixture.message(noon.addingTimeInterval(-2900)),
            CodexFixture.usageRecord(noon.addingTimeInterval(-2000), responseID: "r-2", total: 2_500),
        ], modified: noon)

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.tokensToday == 3_500)
        #expect(snapshot.activity.requestsToday == 2)
        #expect(snapshot.recentModel == "gpt-example-1")

        // Yesterday's response is left out of today, but not out of the history.
        let history = try #require(snapshot.activity.history)
        #expect(history.days.map(\.tokens).suffix(2) == [9_000, 3_500])
        #expect(history.tokens == 12_500)
    }

    @Test func respectsLocalDayBoundary() async throws {
        let dir = try TemporaryDirectory()
        let midnight = TestDates.utc.startOfDay(for: noon)
        try dir.writeJSONL("sessions/rollout-a.jsonl", lines: [
            CodexFixture.usageRecord(midnight.addingTimeInterval(-1), responseID: "before", total: 100),
            CodexFixture.usageRecord(midnight, responseID: "at", total: 200),
        ], modified: noon)

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.tokensToday == 200)
        #expect(snapshot.activity.requestsToday == 1)
    }

    /// Files are chosen by modification date before they're opened, so one
    /// untouched since before the history began is never read.
    @Test func ignoresFilesNotModifiedWithinTheHistory() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("sessions/rollout-old.jsonl", lines: [
            CodexFixture.usageRecord(noon, responseID: "r-1", total: 100),
        ], modified: noon.addingTimeInterval(-31 * 86_400))

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.tokensToday == 0)
        #expect(snapshot.activity.history?.hasActivity == false)
    }

    @Test func countsForkedResponsesOnce() async throws {
        let dir = try TemporaryDirectory()
        let record = CodexFixture.usageRecord(noon.addingTimeInterval(-60), responseID: "r-shared", total: 700)
        try dir.writeJSONL("sessions/rollout-a.jsonl", lines: [record], modified: noon)
        try dir.writeJSONL("archived_sessions/rollout-b.jsonl", lines: [record], modified: noon)

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.tokensToday == 700)
        #expect(snapshot.activity.requestsToday == 1)
    }

    @Test func toleratesMalformedAndPartialLines() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("sessions/rollout-a.jsonl", lines: [
            "not json at all",
            #"{"type":"token_usage_record","payload":{"usage":"wrong type"}}"#,
            #"{"timestamp":"garbage","type":"token_usage_record","payload":{"usage":{"total_tokens":5}}}"#,
            CodexFixture.usageRecord(noon.addingTimeInterval(-60), responseID: "r-1", total: 300),
            #"{"timestamp":"2026-09-11T11:59:00Z","type":"token_usage_record","payload":{"usa"#,
        ], modified: noon, trailingNewline: false)

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.tokensToday == 300)
        #expect(snapshot.activity.requestsToday == 1)
    }

    @Test func readsAppendedLinesIncrementally() async throws {
        let dir = try TemporaryDirectory()
        let file = try dir.writeJSONL("sessions/rollout-a.jsonl", lines: [
            CodexFixture.usageRecord(noon.addingTimeInterval(-600), responseID: "r-1", total: 100),
        ], modified: noon.addingTimeInterval(-600))
        let codex = provider(environment(dir, executable: false))

        #expect(try await codex.fetchSnapshot(trigger: .automatic).activity.tokensToday == 100)

        try dir.append([CodexFixture.usageRecord(noon.addingTimeInterval(-60), responseID: "r-2", total: 50)], to: file, modified: noon)
        let updated = try await codex.fetchSnapshot(trigger: .automatic)
        #expect(updated.activity.tokensToday == 150)
        #expect(updated.activity.requestsToday == 2)
    }

    @Test func fallsBackToLegacyTokenCounts() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("sessions/rollout-legacy.jsonl", lines: [
            CodexFixture.tokenCount(noon.addingTimeInterval(-300), cumulative: 1_000, last: 1_000),
            CodexFixture.tokenCount(noon.addingTimeInterval(-299), cumulative: 1_000, last: 1_000), // repeat
            CodexFixture.tokenCount(noon.addingTimeInterval(-200), cumulative: 1_600, last: 600),
        ], modified: noon)

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.tokensToday == 1_600)
        #expect(snapshot.activity.requestsToday == 2)
    }

    /// Older Codex versions record the cache split in `token_count` too, so
    /// those sessions are priced like current ones.
    @Test func pricesLegacyTokenCountsThatRecordASplit() async throws {
        let dir = try TemporaryDirectory()
        let usage = #"{"input_tokens":1000000,"cached_input_tokens":0,"output_tokens":0,"total_tokens":1000000}"#
        try dir.writeJSONL("sessions/rollout-legacy.jsonl", lines: [
            CodexFixture.turnContext(noon.addingTimeInterval(-400), model: "gpt-5-codex"),
            #"{"timestamp":"\#(TestDates.iso(noon.addingTimeInterval(-300)))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(usage),"last_token_usage":\#(usage)}}}"#,
        ], modified: noon)

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.estimatedCostToday == Decimal(string: "1.25"))
        #expect(snapshot.activity.isCostComplete)
    }

    // MARK: Quota

    @Test func rendersOnlyReportedWindows() async throws {
        let dir = try TemporaryDirectory()
        let weeklyOnly = CodexRateLimitSnapshot(
            windows: [.init(usedPercent: 42, durationMinutes: 10_080, resetsAt: noon.addingTimeInterval(4 * 86_400))],
            planType: "plus",
            capturedAt: noon
        )
        let snapshot = try await provider(environment(dir), appServer: { _ in .rateLimits(weeklyOnly) }).fetchSnapshot(trigger: .automatic)

        #expect(snapshot.windows.map(\.kind) == [.weekly])
        #expect(snapshot.window(.weekly)?.usage?.displayValue == 42)
        #expect(snapshot.window(.fiveHour) == nil)
        #expect(snapshot.planName == "Plus")
        #expect(snapshot.capabilities.isSuperset(of: [.quota, .resetTimes, .planInformation, .tokenActivity]))
    }

    @Test func windowsAreIdentifiedByDurationNotPosition() {
        let limits = CodexRateLimitSnapshot(
            windows: [
                .init(usedPercent: 10, durationMinutes: 10_080, resetsAt: nil),
                .init(usedPercent: 60, durationMinutes: 300, resetsAt: nil),
                .init(usedPercent: 5, durationMinutes: 43_200, resetsAt: nil),
                .init(usedPercent: 99, durationMinutes: nil, resetsAt: nil),
            ],
            planType: nil,
            capturedAt: noon
        )
        #expect(limits.usageWindows(at: noon).map(\.kind) == [.fiveHour, .weekly, .custom(minutes: 43_200)])
    }

    @Test func fallsBackToRecordedLimitsWhenAppServerFails() async throws {
        let dir = try TemporaryDirectory()
        let resets = noon.addingTimeInterval(3 * 86_400)
        try dir.writeJSONL("sessions/2026/09/08/rollout-a.jsonl", lines: [
            CodexFixture.rateLimitsOnly(noon.addingTimeInterval(-2 * 86_400), limits: CodexFixture.limits(primaryPercent: 30, primaryMinutes: 10_080, resetsAt: resets)),
        ], modified: noon.addingTimeInterval(-2 * 86_400))

        let snapshot = try await provider(environment(dir), appServer: { _ in throw CodexAppServerClient.ClientError.timedOut })
            .fetchSnapshot(trigger: .automatic)

        #expect(snapshot.status == .available)
        #expect(snapshot.window(.weekly)?.usage?.displayValue == 30)
        #expect(snapshot.limitsUpdatedAt == noon.addingTimeInterval(-2 * 86_400))
        #expect(snapshot.isStale(at: noon))
    }

    @Test func dropsWindowsThatResetSinceCapture() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("sessions/rollout-a.jsonl", lines: [
            CodexFixture.rateLimitsOnly(noon.addingTimeInterval(-3 * 86_400), limits: CodexFixture.limits(primaryPercent: 80, primaryMinutes: 300, resetsAt: noon.addingTimeInterval(-2 * 86_400))),
        ], modified: noon.addingTimeInterval(-3 * 86_400))

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.isEmpty)
        #expect(!snapshot.capabilities.contains(.quota))
    }

    @Test func newerRecordedLimitsBeatOlderServerResult() async throws {
        let dir = try TemporaryDirectory()
        let resets = noon.addingTimeInterval(86_400)
        try dir.writeJSONL("sessions/rollout-a.jsonl", lines: [
            CodexFixture.rateLimitsOnly(noon.addingTimeInterval(-10), limits: CodexFixture.limits(primaryPercent: 55, primaryMinutes: 10_080, resetsAt: resets)),
        ], modified: noon)
        let older = CodexRateLimitSnapshot(windows: [.init(usedPercent: 40, durationMinutes: 10_080, resetsAt: resets)], planType: "plus", capturedAt: noon.addingTimeInterval(-120))

        let snapshot = try await provider(environment(dir), appServer: { _ in .rateLimits(older) }).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.window(.weekly)?.usage?.displayValue == 55)
    }

    @Test func apiKeyAccountsHaveNoQuota() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir), appServer: { _ in .noSubscriptionLimits }).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func cachesAppServerBetweenAutomaticRefreshes() async throws {
        let dir = try TemporaryDirectory()
        let calls = CallCounter()
        let limits = CodexRateLimitSnapshot(windows: [.init(usedPercent: 1, durationMinutes: 300, resetsAt: nil)], planType: nil, capturedAt: noon)
        let codex = provider(environment(dir), appServer: { _ in
            await calls.increment()
            return .rateLimits(limits)
        })

        _ = try await codex.fetchSnapshot(trigger: .automatic)
        _ = try await codex.fetchSnapshot(trigger: .automatic)
        #expect(await calls.count == 1)

        _ = try await codex.fetchSnapshot(trigger: .manual)
        #expect(await calls.count == 2)
    }

    // MARK: Wire formats

    @Test func decodesAppServerRateLimits() throws {
        let json = #"""
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1789487584},"secondary":null,"planType":"plus","somethingNew":true},"accountId":"acct-example"}
        """#
        let result = try JSONDecoder().decode(CodexAppServerRateLimitsResult.self, from: Data(json.utf8))
        let snapshot = result.snapshot(capturedAt: noon)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.durationMinutes == 10_080)
        #expect(snapshot.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_789_487_584))
        #expect(snapshot.planType == "plus")
    }

    @Test(arguments: zip(
        ["plus", "pro", "prolite", "team", "free", "PLUS", "enterprise_cbp_usage_based", "unknown", ""],
        ["Plus", "Pro", "Pro Lite", "Team", "Free", "Plus", "Enterprise", nil, nil] as [String?]
    ))
    func planNames(planType: String, expected: String?) {
        #expect(CodexPlan.displayName(for: planType) == expected)
    }
}

actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

extension CodexProviderTests {
    // MARK: Models and plans (0.3.0)

    @Test func responsesAreAttributedToTheirTurnsModel() async throws {
        let dir = try TemporaryDirectory()
        try dir.writeJSONL("sessions/2026/09/11/rollout-models.jsonl", lines: [
            CodexFixture.turnContext(noon.addingTimeInterval(-600), model: "gpt-example-large"),
            CodexFixture.usageRecord(noon.addingTimeInterval(-590), responseID: "r1", total: 5_000),
            CodexFixture.usageRecord(noon.addingTimeInterval(-580), responseID: "r2", total: 3_000),
            CodexFixture.turnContext(noon.addingTimeInterval(-300), model: "gpt-example-mini"),
            CodexFixture.usageRecord(noon.addingTimeInterval(-290), responseID: "r3", total: 1_000),
        ], modified: noon)

        let snapshot = try await provider(environment(dir, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.modelActivity.map(\.modelID) == ["gpt-example-large", "gpt-example-mini"])
        #expect(snapshot.modelActivity.first?.totalTokens == 8_000)
        #expect(snapshot.modelActivity.first?.requests == 2)
        #expect(snapshot.modelActivity.first?.outputTokens == 200)
        #expect(snapshot.recentModel == "gpt-example-mini")
    }

    @Test func planComesFromTheAccountWhenRateLimitsAreMissing() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir), appServer: { _ in .signedInWithoutRateLimits(planType: "team") }).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.planName == "Team")
        #expect(snapshot.windows.isEmpty, "No limits are estimated for a Team account without them")
    }

    @Test func teamWithoutServerLimitsStillUsesRecordedLimits() async throws {
        let dir = try TemporaryDirectory()
        let limits = CodexFixture.limits(primaryPercent: 30, primaryMinutes: 300, resetsAt: noon.addingTimeInterval(3_600), plan: "team")
        try dir.writeJSONL("sessions/2026/09/11/rollout-team.jsonl", lines: [
            CodexFixture.rateLimitsOnly(noon.addingTimeInterval(-60), limits: limits),
        ], modified: noon)

        let snapshot = try await provider(environment(dir), appServer: { _ in .signedInWithoutRateLimits(planType: "team") }).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.window(.fiveHour)?.usage?.displayValue == 30)
        #expect(snapshot.planName == "Team")
    }

    @Test(arguments: [
        ("business", "Business"),
        ("self_serve_business_usage_based", "Business"),
        ("self_serve_business_prolite", "Business"),
        ("edu_plus", "Edu Plus"),
        ("edu_pro", "Edu Pro"),
        ("ent26", nil),
    ] as [(String, String?)])
    func billingVariantsOfNamedPlans(planType: String, expected: String?) {
        #expect(CodexPlan.displayName(for: planType) == expected)
    }
}
