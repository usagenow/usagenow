import Foundation
import Synchronization
import Testing
@testable import UsageNow

/// Antigravity's experimental limits. The response and sign-in shapes come
/// from open implementations of the same endpoint; they haven't been checked
/// against a live account by these tests.
struct AntigravityProviderTests {
    private let noon = TestDates.noon

    private func environment(installed: Bool = true, signedIn: Bool = true) -> AntigravityEnvironment {
        AntigravityEnvironment(
            home: URL(filePath: "/nonexistent/.gemini/antigravity-cli"),
            homeExists: installed,
            executable: nil,
            projectID: "example-project-123",
            hasSavedSignIn: signedIn
        )
    }

    private func provider(_ environment: AntigravityEnvironment, client: AntigravityQuotaClient? = nil, enabled: Bool = true) -> AntigravityProvider {
        AntigravityProvider(discover: { environment }, limitsClient: client, limitsEnabled: FeatureSwitch(enabled), now: { TestDates.noon })
    }

    private func client(
        _ credentials: any CredentialSource,
        status: Int = 200,
        body: String = AntigravityFixture.summary,
        store: QuotaCacheStore<[UsageWindow]>? = nil,
        transport: StubTransport? = nil
    ) -> AntigravityQuotaClient {
        AntigravityQuotaClient(
            credentials: credentials,
            transport: transport ?? StubTransport(status: status, body: body),
            minimumInterval: 0,
            lastKnownLimits: store,
            projectID: { "example-project-123" }
        )
    }

    private var freshToken: CredentialLookup {
        .found(OAuthAccessToken(value: "fake-google-token", expiresAt: TestDates.noon.addingTimeInterval(1_800)))
    }

    // MARK: States

    @Test func notInstalled() async throws {
        #expect(try await provider(environment(installed: false)).fetchSnapshot(trigger: .automatic).status == .notInstalled)
    }

    @Test func installedWithoutSignIn() async throws {
        #expect(try await provider(environment(signedIn: false)).fetchSnapshot(trigger: .automatic).status == .notAuthenticated)
    }

    @Test func settingOffNeverReadsTheKeychainOrNetwork() async throws {
        let credentials = SequencedCredentials([freshToken])
        let transport = StubTransport(status: 200, body: AntigravityFixture.summary)
        let snapshot = try await provider(environment(), client: client(credentials, transport: transport), enabled: false).fetchSnapshot(trigger: .manual)

        #expect(snapshot.status == .available)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.quotaUnavailableReason == nil)
        #expect(await credentials.reads == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test func groupsBecomeScopedWeeklyWindows() async throws {
        let snapshot = try await provider(environment(), client: client(SequencedCredentials([freshToken]))).fetchSnapshot(trigger: .manual)

        #expect(snapshot.windows.map(\.kind) == [.weekly, .weekly])
        #expect(snapshot.windows.map(\.scope) == ["Claude and GPT", "Gemini"])
        #expect(snapshot.windows.first { $0.scope == "Gemini" }?.usage?.remainingDisplayValue == 75)
        #expect(snapshot.windows.first { $0.scope == "Claude and GPT" }?.usage?.remainingDisplayValue == 10)
        #expect(snapshot.mostCriticalWindow?.scope == "Claude and GPT")
        #expect(snapshot.modelActivity.isEmpty, "No activity is guessed from agy's binary conversation files")
    }

    @Test func requestGoesOnlyToCloudCodeWithTheProject() async throws {
        let transport = StubTransport(status: 200, body: AntigravityFixture.summary)
        _ = await client(SequencedCredentials([freshToken]), transport: transport).windows(trigger: .manual, now: { TestDates.noon })

        let request = try #require(await transport.requests.first)
        #expect(request.url == AntigravityQuotaClient.endpoint)
        #expect(request.url?.host() == "daily-cloudcode-pa.googleapis.com")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-google-token")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["project": "example-project-123"])
    }

    // MARK: Sign-in lifecycle

    @Test func expiredSignInIsNeverSentAndIsPickedUpOnceAgySavesANewOne() async throws {
        let credentials = SequencedCredentials(
            [.found(OAuthAccessToken(value: "expired", expiresAt: TestDates.noon.addingTimeInterval(-60)))],
            modified: TestDates.noon.addingTimeInterval(-3_600)
        )
        let transport = StubTransport(status: 200, body: AntigravityFixture.summary)
        let client = client(credentials, transport: transport)
        let clock = TestClock(TestDates.noon)

        #expect(await client.windows(trigger: .automatic, now: { clock.now }) == nil)
        #expect(await client.availability == .staleAuthentication)
        clock.advance(by: 300)
        _ = await client.windows(trigger: .automatic, now: { clock.now })
        #expect(await credentials.reads == 1, "Unchanged sign-in isn't read again")
        #expect(await transport.requests.isEmpty)

        await credentials.save(.found(OAuthAccessToken(value: "renewed", expiresAt: clock.now.addingTimeInterval(3_600))), at: clock.now)
        clock.advance(by: 300)
        #expect(await client.windows(trigger: .automatic, now: { clock.now })?.value.count == 2)
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed")
    }

    @Test func rejectedTokenWaitsForANewSignIn() async throws {
        let credentials = SequencedCredentials([freshToken], modified: TestDates.noon)
        let client = client(credentials, status: 401, body: "{}")
        _ = await client.windows(trigger: .automatic, now: { TestDates.noon })
        _ = await client.windows(trigger: .automatic, now: { TestDates.noon })
        #expect(await credentials.reads == 1)
        #expect(await client.availability == .staleAuthentication)
    }

    @Test func unreadableSignInIsOnlyRetriedManually() async throws {
        let credentials = SequencedCredentials([.accessDenied])
        let client = client(credentials)
        _ = await client.windows(trigger: .automatic, now: { TestDates.noon })
        _ = await client.windows(trigger: .automatic, now: { TestDates.noon })
        #expect(await credentials.reads == 1)
        #expect(await client.availability == .keychainDenied)
        _ = await client.windows(trigger: .manual, now: { TestDates.noon })
        #expect(await credentials.reads == 2)
    }

    @Test func staleSignInKeepsLastLimitsAcrossARelaunch() async throws {
        let memory = MemoryQuotaStore()
        _ = await client(SequencedCredentials([freshToken]), store: memory.store).windows(trigger: .manual, now: { TestDates.noon })

        let later = client(SequencedCredentials([.found(OAuthAccessToken(value: "expired", expiresAt: TestDates.noon))]), store: memory.store)
        let snapshot = try await provider(environment(), client: later).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.count == 2, "Last known limits stay, marked stale")
        #expect(snapshot.limitsUpdatedAt == TestDates.noon)
    }

    @Test func turningItOffForgetsEverything() async throws {
        let memory = MemoryQuotaStore()
        let client = client(SequencedCredentials([freshToken]), store: memory.store)
        _ = await client.windows(trigger: .manual, now: { TestDates.noon })
        await client.reset()
        #expect(memory.stored == nil)
        #expect(await client.availability == .disabled)
    }

    @Test func unsupportedResponseIsTemporarilyUnavailable() async throws {
        let client = client(SequencedCredentials([freshToken]), body: #"{"somethingElse":true}"#)
        #expect(await client.windows(trigger: .manual, now: { TestDates.noon }) == nil)
        #expect(await client.availability == .unsupportedResponse)
    }

    // MARK: Parsing

    @Test func parserAcceptsNestedRemainingAndWrappedSummaries() throws {
        let nested = #"{"quotaSummary":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini_weekly","remaining":{"remainingFraction":"0.5","resetTime":"2026-09-15T00:00:00Z"}}]}]}}"#
        let windows = try #require(AntigravityQuotaParser.windows(from: Data(nested.utf8)))
        #expect(windows.first?.usage?.remainingDisplayValue == 50)
        #expect(windows.first?.resetsAt == SessionTimestamp.parse("2026-09-15T00:00:00Z"))
    }

    @Test func parserSkipsWhatItCantLabel() throws {
        let json = #"{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"mystery","remainingFraction":0.2},{"bucketId":"weekly","disabled":true,"remainingFraction":0.1},{"bucketId":"weekly"},{"displayName":"5-hour limit","remainingFraction":1.4}]}]}"#
        let windows = try #require(AntigravityQuotaParser.windows(from: Data(json.utf8)))
        #expect(windows.count == 1)
        #expect(windows.first?.kind == .fiveHour)
        #expect(windows.first?.usage?.remainingDisplayValue == 100, "Fractions are clamped")
        #expect(AntigravityQuotaParser.windows(from: Data("[]".utf8)) == nil)
    }

    @Test(arguments: [
        ("Gemini Models", "Gemini"),
        ("Claude and GPT Models", "Claude and GPT"),
        ("Something New", "Something New"),
    ])
    func scopeNames(displayName: String, expected: String) {
        #expect(AntigravityQuotaParser.scopeName(displayName) == expected)
    }

    @Test func tokenParserAcceptsCommonShapes() {
        let goStyle = #"{"access_token":"a","token_type":"Bearer","refresh_token":"r","expiry":"2026-09-11T13:00:00.123456789+01:00"}"#
        let token = AntigravityTokenParser.token(from: Data(goStyle.utf8))
        #expect(token?.value == "a")
        let expected = SessionTimestamp.parse("2026-09-11T12:00:00Z") ?? .distantFuture
        #expect(abs((token?.expiresAt ?? .distantPast).timeIntervalSince(expected)) < 1, "RFC 3339 with an offset and nanoseconds")

        let wrapped = "go-keyring-base64:" + Data(#"{"token":{"accessToken":"b","expiry_date":1789128000000}}"#.utf8).base64EncodedString()
        let unwrapped = AntigravityTokenParser.token(from: Data(wrapped.utf8))
        #expect(unwrapped?.value == "b")
        #expect(unwrapped?.expiresAt == Date(timeIntervalSince1970: 1_789_128_000))

        let hex = "go-keyring-encoded:" + Data(#"{"access_token":"c","expires_at":1789128000}"#.utf8).map { String(format: "%02x", $0) }.joined()
        #expect(AntigravityTokenParser.token(from: Data(hex.utf8))?.expiresAt == Date(timeIntervalSince1970: 1_789_128_000))

        #expect(AntigravityTokenParser.token(from: Data("not json".utf8)) == nil)
        #expect(AntigravityTokenParser.token(from: Data(#"{"refresh_token":"r"}"#.utf8)) == nil)
    }

    @Test func formatDiagnosticsNeverIncludeValues() {
        let shape = AntigravityTokenParser.shape(of: Data(#"{"refresh_token":"secret-refresh","weird":"secret-value"}"#.utf8))
        #expect(shape == "wrapping none, keys refresh_token,weird")
        #expect(!shape.contains("secret"))
    }

    @Test func securityToolStatusesMapToLookups() {
        guard case .notFound = KeychainAntigravityCredentialSource.lookup(exitStatus: SecurityTool.itemNotFoundStatus, output: Data()) else {
            Issue.record("A missing item is not a denial"); return
        }
        guard case .accessDenied = KeychainAntigravityCredentialSource.lookup(exitStatus: 51, output: Data()) else {
            Issue.record("Other failures stop automatic reads"); return
        }
        guard case .found = KeychainAntigravityCredentialSource.lookup(exitStatus: 0, output: Data(#"{"access_token":"x"}"#.utf8 + [0x0A])) else {
            Issue.record("A saved sign-in is found"); return
        }
    }

    @Test func projectIDIsReadOnlyWhenPlausible() throws {
        let dir = try TemporaryDirectory()
        try dir.write("cache/default_project_id.txt", text: "example-project-123\n")
        #expect(AntigravityEnvironment.projectID(in: dir.url) == "example-project-123")
        try dir.write("cache/default_project_id.txt", text: "not a project; rm -rf /")
        #expect(AntigravityEnvironment.projectID(in: dir.url) == nil)
    }

    @Test func messagesNameTheRightTool() {
        #expect(QuotaUnavailableReason.signInExpired.message(for: .antigravity).contains("Antigravity"))
        #expect(QuotaUnavailableReason.signInExpired.message(for: .claudeCode).contains("Claude Code"))
        #expect(QuotaUnavailableReason.temporarilyUnavailable.message(for: .antigravity).contains("Antigravity"))
    }
}

enum AntigravityFixture {
    static let summary = #"""
    {
      "groups": [
        {
          "displayName": "Gemini Models",
          "buckets": [
            {"bucketId": "gemini_weekly", "displayName": "Weekly Limit", "remainingFraction": 0.75, "resetTime": "2026-09-15T00:00:00Z"}
          ]
        },
        {
          "displayName": "Claude and GPT Models",
          "buckets": [
            {"bucketId": "claude_gpt_weekly", "displayName": "Weekly Limit", "remainingFraction": 0.1, "resetTime": "2026-09-15T00:00:00Z"},
            {"bucketId": "future_bucket", "displayName": "Something new"}
          ]
        }
      ]
    }
    """#
}
