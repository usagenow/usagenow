import Foundation
import Synchronization
import Testing
@testable import UsageNow

private func payload(_ json: String) -> Data { Data(json.utf8) }

struct ConnectedProviderParsingTests {
    @Test func elevenLabsUsesCharactersAndExplicitReset() throws {
        let reading = try ElevenLabsUsage.parse(payload(#"{"character_count":250,"character_limit":1000,"next_character_count_reset_unix":1800000000,"tier":"creator"}"#))
        #expect(reading.planName == "creator")
        #expect(reading.windows.first?.kind == .monthly)
        #expect(reading.windows.first?.usage?.value == 25)
        #expect(reading.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reading.totals == [UsageTotal(kind: .charactersUsed, value: 250)])
        #expect(reading.balance == nil)
    }

    @Test func elevenLabsZeroLimitIsNotExhaustion() throws {
        let reading = try ElevenLabsUsage.parse(payload(#"{"character_count":0,"character_limit":0}"#))
        #expect(reading.windows.isEmpty)
        #expect(reading.totals.first?.value == 0)
    }

    @Test(arguments: [#"{}"#, #"{"character_count":-1,"character_limit":20}"#, #"{"character_count":0}"#, "<html>Sign in</html>"])
    func elevenLabsRejectsMissingOrInvalidCounts(_ body: String) {
        #expect(throws: APIKeyClient.Failure.unreadableResponse) { try ElevenLabsUsage.parse(payload(body)) }
    }

    @Test func cursorPercentIsNotAFraction() throws {
        let reading = try CursorUsage.parse(payload(#"{"membershipType":"pro","individualUsage":{"plan":{"totalPercentUsed":0.36}},"billingCycleEnd":"2026-11-02T00:00:00.000Z"}"#))
        #expect(reading.windows.first?.usage?.value == 0.36)
        #expect(reading.windows.first?.resetsAt != nil)
        #expect(reading.planName == "pro")
    }

    @Test func cursorUsesPersonalCountsAndNeverSubstitutesTeamPool() throws {
        let reading = try CursorUsage.parse(payload(#"{"individualUsage":{"plan":{"used":25,"limit":100,"totalPercentUsed":0}},"teamUsage":{"pooled":{"used":90,"limit":100}}}"#))
        #expect(reading.windows.count == 1)
        #expect(reading.windows[0].usage?.value == 25)
        #expect(reading.windows[0].scope == nil)
        #expect(throws: APIKeyClient.Failure.unreadableResponse) {
            try CursorUsage.parse(payload(#"{"teamUsage":{"pooled":{"used":90,"limit":100}}}"#))
        }
    }

    @Test func cursorUnlimitedIsNotAFullAllowance() throws {
        let reading = try CursorUsage.parse(payload(#"{"membershipType":"team","isUnlimited":true,"individualUsage":{"plan":{"used":0,"limit":100}}}"#))
        #expect(reading.windows.isEmpty)
        #expect(reading.planName == "team")
    }

    @Test func cursorDisabledPlanFallsBackToOverall() throws {
        let reading = try CursorUsage.parse(payload(#"{"individualUsage":{"plan":{"enabled":false,"used":10,"limit":10},"overall":{"limit":100,"remaining":80}}}"#))
        #expect(reading.windows.first?.usage?.value == 20)
    }

    @Test func cursorDoesNotInventAllowanceFromBreakdownOrAverage() {
        #expect(throws: APIKeyClient.Failure.unreadableResponse) {
            try CursorUsage.parse(payload(#"{"individualUsage":{"plan":{"autoPercentUsed":50,"apiPercentUsed":80,"breakdown":{"total":100}}}}"#))
        }
    }

    @Test func copilotSupportsPercentCountsAndStringCounters() throws {
        let reading = try CopilotUsage.parse(payload(#"{"copilot_plan":"individual","quota_reset_date":"2026-11-01","quota_snapshots":{"premium_interactions":{"entitlement":"1000","remaining":"750"},"chat":{"percent_remaining":80}}}"#))
        #expect(reading.windows.count == 2)
        #expect(reading.windows.map { $0.usage?.value } == [25, 20])
        #expect(reading.windows[0].resetsAt == ConnectedUsage.date("2026-11-01T00:00:00Z"))
        #expect(reading.planName == "individual")
    }

    @Test func copilotTokenBillingPlaceholderAndUnlimitedAreNotPercentages() throws {
        let reading = try CopilotUsage.parse(payload(#"{"copilot_plan":"business","token_based_billing":true,"quota_snapshots":{"premium_interactions":{"entitlement":0,"remaining":0,"percent_remaining":100,"credits_used":12.5},"chat":{"unlimited":true,"percent_remaining":100,"credits_used":12.5}}}"#))
        #expect(reading.windows.isEmpty)
        #expect(reading.totals == [UsageTotal(kind: .creditsUsed, value: Decimal(string: "12.5")!)])
    }

    @Test func copilotPlanOnlyIsNotAFullAllowance() throws {
        let reading = try CopilotUsage.parse(payload(#"{"copilot_plan":"enterprise","quota_snapshots":{"chat":{"unlimited":true}}}"#))
        #expect(reading.windows.isEmpty)
        #expect(reading.totals.isEmpty)
    }

    @Test func copilotDoesNotGuessUnknownQuotas() {
        #expect(throws: APIKeyClient.Failure.unreadableResponse) {
            try CopilotUsage.parse(payload(#"{"quota_snapshots":{"future_pool":{"percent_remaining":99}}}"#))
        }
    }

    @Test func copilotLegacyFreePlanUsesReportedCapAndRemaining() throws {
        let reading = try CopilotUsage.parse(payload(#"{"copilot_plan":"free","monthly_quotas":{"chat":50,"completions":2000},"limited_user_quotas":{"chat":20,"completions":1800}}"#))
        #expect(reading.windows.map { $0.usage?.value } == [60, 10])
        let incomplete = try CopilotUsage.parse(payload(#"{"copilot_plan":"free","monthly_quotas":{"chat":50}}"#))
        #expect(incomplete.windows.isEmpty)
    }

    @Test func perplexityRecurringPoolHasActualRenewalNotInventedCadence() throws {
        let reading = try PerplexityUsage.parse(payload(#"{"balance_cents":700,"total_usage_cents":300,"renewal_date_ts":1800000000,"credit_grants":[{"type":"recurring","amount_cents":1000}]}"#))
        #expect(reading.windows.first?.kind == .allowance)
        #expect(reading.windows.first?.usage?.value == 30)
        #expect(reading.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reading.planName == nil, "No guessed Pro/Max plan")
        #expect(reading.balance == nil, "Credits must not be labeled dollars")
        #expect(reading.totals.map(\.value) == [700, 300])
    }

    @Test func perplexityMixedPoolsNeverGetAFalseReset() throws {
        let reading = try PerplexityUsage.parse(payload(#"{"balanceCents":700,"totalUsageCents":300,"renewalDateTs":1800000000,"creditGrants":[{"type":"recurring","amountCents":500},{"type":"purchased","amountCents":500}]}"#))
        #expect(reading.windows.first?.usage?.value == 30)
        #expect(reading.windows.first?.resetsAt == nil)
    }

    @Test(arguments: [#"[]"#, #"[{"type":"promotional","amount_cents":1000,"expires_at_ts":1}]"#, #"[{"type":"purchased","amount_cents":500}]"#, #"[{"type":"new_kind","amount_cents":1000}]"#])
    func perplexityUnreconciledPoolsStillShowActualCounters(_ grants: String) throws {
        let reading = try PerplexityUsage.parse(payload("{\"balance_cents\":700,\"total_usage_cents\":300,\"credit_grants\":\(grants)}"))
        #expect(reading.windows.isEmpty)
        #expect(reading.totals.count == 2)
    }

    @Test func emptyPerplexityAccountIsNot100PercentUsed() throws {
        let reading = try PerplexityUsage.parse(payload(#"{"balance_cents":0,"total_usage_cents":0,"credit_grants":[]}"#))
        #expect(reading.windows.isEmpty)
        #expect(reading.totals.map(\.value) == [0, 0])
    }

    @Test func zaiReadsWindowsAndMCPWithoutHardcodingFiveHourWeeklyPositions() throws {
        let reading = try ZaiUsage.parse(payload(#"{"success":true,"code":200,"data":{"planName":"GLM Coding Pro","limits":[{"type":"TIME_LIMIT","unit":5,"number":1,"percentage":20},{"type":"TOKENS_LIMIT","unit":6,"number":1,"usage":100,"remaining":60,"percentage":0},{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":15,"nextResetTime":1800000000000},{"type":"FUTURE_LIMIT"}]}}"#), now: Date(timeIntervalSince1970: 1_799_999_000))
        #expect(reading.windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        #expect(reading.windows.map { $0.usage?.value } == [15, 40, 20])
        #expect(reading.windows.last?.scope == "MCP")
        #expect(reading.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func zaiDropsImplausibleFiveHourResetAndDeduplicates() throws {
        let reading = try ZaiUsage.parse(payload(#"{"success":true,"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":10},{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":70,"nextResetTime":1900000000000}]}}"#), now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reading.windows.count == 1)
        #expect(reading.windows.first?.usage?.value == 70)
        #expect(reading.windows.first?.resetsAt == nil)
    }

    @Test(arguments: [#"{}"#, #"{"success":true,"code":200,"data":{"limits":[]}}"#, #"{"success":false,"code":401,"data":{"limits":[]}}"#])
    func zaiRejectsEmptyUnknownAndFailedResponses(_ body: String) {
        #expect(throws: APIKeyClient.Failure.unreadableResponse) { try ZaiUsage.parse(payload(body)) }
    }

    @Test func allowanceWindowRoundTripsWithoutBecomingMonthly() throws {
        let window = UsageWindow(kind: .allowance, usage: UsagePercentage(percent: 25), resetsAt: nil)
        let decoded = try JSONDecoder().decode(UsageWindow.self, from: JSONEncoder().encode(window))
        #expect(decoded == window)
        #expect(window.id != UsageWindow(kind: .monthly, usage: nil, resetsAt: nil).id)
    }
}

struct ConnectionCredentialTests {
    private let cursor = ProviderCatalog.definition(for: .cursor).apiKey!
    private let perplexity = ProviderCatalog.definition(for: .perplexity).apiKey!

    @Test func namedCookieOnlyIsRetained() throws {
        let value = try cursor.normalizedCredential("Cookie: analytics=abc; WorkosCursorSessionToken=fake%3Atoken==; tracking=; tracking=other")
        #expect(value == "WorkosCursorSessionToken=fake%3Atoken==")
    }

    @Test func chunkedCookiesAreOrderedAndKeptUnderTheirNames() throws {
        let value = try perplexity.normalizedCredential("authjs.session-token.1=second; analytics=tracking; authjs.session-token.0=first")
        #expect(value == "authjs.session-token.0=first; authjs.session-token.1=second")
    }

    @Test(arguments: ["tokenWithoutAName", "unrelated=value", "WorkosCursorSessionToken=", "WorkosCursorSessionToken=a\r\nAuthorization: other", "WorkosCursorSessionToken=a; WorkosCursorSessionToken=b", "WorkosCursorSessionToken.1=b", "WorkosCursorSessionToken=a b"])
    func malformedCookiesAreRejected(_ cookie: String) {
        #expect(throws: APIKeyClient.Failure.invalidCredential) { try cursor.normalizedCredential(cookie) }
    }

    @Test func keychainReceivesOnlySelectedCookieAndAccountsStaySeparate() throws {
        let store = KeychainAPIKeyStore(store: InMemorySecureStore())
        try store.setKey("tracking=no; WorkosCursorSessionToken=first", for: .cursor)
        try store.setKey("WorkosCursorSessionToken=second", for: .cursor, account: "work")
        #expect(try store.key(for: .cursor) == "WorkosCursorSessionToken=first")
        #expect(try store.key(for: .cursor, account: "work") == "WorkosCursorSessionToken=second")
        try store.removeKey(for: .cursor)
        #expect(try store.key(for: .cursor) == nil)
        #expect(try store.key(for: .cursor, account: "work") != nil)
    }

    private func cookie(domain: String = ".cursor.com", path: String = "/", secure: Bool = true, expires: Date? = nil) -> HTTPCookie {
        var fields: [HTTPCookiePropertyKey: Any] = [.name: "WorkosCursorSessionToken", .value: "fixture", .domain: domain, .path: path]
        if secure { fields[.secure] = "TRUE" }
        if let expires { fields[.expires] = expires }
        return HTTPCookie(properties: fields)!
    }

    @Test func browserAcceptsOnlyApplicableSecureProviderCookie() throws {
        #expect(try LoginCookieSelection.select([cookie()], connection: cursor) == "WorkosCursorSessionToken=fixture")
        for wrong in [cookie(domain: ".evilcursor.com"), cookie(domain: ".cursor.com.evil.test"), cookie(domain: ".com"), cookie(path: "/dashboard"), cookie(secure: false), cookie(expires: .distantPast)] {
            #expect(throws: APIKeyClient.Failure.invalidCredential) { try LoginCookieSelection.select([wrong], connection: cursor) }
        }
    }

    @Test func elevenLabsSendsOnlyXiAPIKey() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        _ = try await APIKeyClient(connection: ProviderCatalog.definition(for: .elevenlabs).apiKey!, transport: transport)
            .get("/v1/user/subscription", key: "fixture")
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "fixture")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func copilotIdentifiesItselfAsUsageNowNotVSCode() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        _ = try await APIKeyClient(connection: ProviderCatalog.definition(for: .copilot).apiKey!, transport: transport)
            .get("/copilot_internal/user", key: "fixture")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.host == "api.github.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("UsageNow/") == true)
        #expect(request.value(forHTTPHeaderField: "Editor-Version") == nil)
        #expect(request.value(forHTTPHeaderField: "Editor-Plugin-Version") == nil)
    }

    @Test func sessionRequestsStripOtherCookiesAndDoNotSendBearer() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        _ = try await APIKeyClient(connection: perplexity, transport: transport).get("/rest/billing/credits", key: "tracking=no; authjs.session-token=fixture", query: [URLQueryItem(name: "version", value: "2.18")])
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "authjs.session-token=fixture")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.perplexity.ai/account/usage")
        #expect(request.url?.query == "version=2.18")
    }

    @Test func elevenLabsPermissionDeniedIsNotAnExpiredSignIn() async {
        let transport = StubTransport(status: 403, body: #"{"detail":{"code":"missing_permissions"}}"#)
        let client = APIKeyClient(connection: ProviderCatalog.definition(for: .elevenlabs).apiKey!, transport: transport)
        await #expect(throws: APIKeyClient.Failure.permissionDenied) { try await client.get("/v1/user/subscription", key: "fixture") }
    }

    @Test func credentialInjectionNeverSendsARequest() async {
        let transport = StubTransport(status: 200, body: "{}")
        let client = APIKeyClient(connection: cursor, transport: transport)
        await #expect(throws: APIKeyClient.Failure.invalidCredential) { try await client.get("/api/usage-summary", key: "WorkosCursorSessionToken=fake\nAuthorization: injected") }
        #expect(await transport.requests.isEmpty)
    }
}

@MainActor
struct ConnectedProviderIntegrationTests {
    private let ids: Set<ProviderID> = [.cursor, .copilot, .perplexity, .elevenlabs, .zai]

    @Test func newConnectionsAreOptInAndHaveNoTelemetryEvents() async {
        let preferences = ProviderPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(preferences.enabledProviders.isDisjoint(with: ids))
        for id in ids {
            #expect(ProviderAccount.kind(for: id) == .apiKey)
            #expect(ProviderCatalog.definition(for: id).apiKey != nil)
            #expect(TelemetryEvent.detected(id) == nil)
        }
        let keys = CountingConnectionKeys()
        let providers = [APIKeyProvider.cursor(keys: keys), .copilot(keys: keys), .perplexity(keys: keys), .elevenLabs(keys: keys), .zai(keys: keys)]
        let store = UsageStore(providers: providers, enabledProviders: [])
        await store.refresh(trigger: .manual)
        #expect(keys.readCount == 0, "Launching with disabled providers never reads Keychain")
    }

    @Test func missingKeyDoesNotContactService() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        let provider = APIKeyProvider.cursor(keys: KeychainAPIKeyStore(store: InMemorySecureStore()), transport: transport)
        #expect(try await provider.fetchSnapshot(trigger: .manual).status == .notInstalled)
        #expect(await transport.requests.isEmpty)
    }

    @Test func rejectedSessionShowsDisconnectedInsteadOfZeroQuota() async throws {
        let keys = KeychainAPIKeyStore(store: InMemorySecureStore())
        try keys.setKey("WorkosCursorSessionToken=fixture", for: .cursor)
        let provider = APIKeyProvider.cursor(keys: keys, transport: StubTransport(status: 401, body: "{}"))
        let snapshot = try await provider.fetchSnapshot(trigger: .manual)
        #expect(snapshot.status == .notAuthenticated)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func replacingCredentialDiscardsOldAccountAndInFlightResult() async throws {
        let keys = KeychainAPIKeyStore(store: InMemorySecureStore())
        try keys.setKey("fixture", for: .elevenlabs)
        let transport = StubTransport(status: 200, body: #"{"character_count":10,"character_limit":100}"#, delay: .milliseconds(100))
        let provider = APIKeyProvider.elevenLabs(keys: keys, transport: transport)
        let store = UsageStore(providers: [provider])
        let request = Task { await store.refresh() }
        while await transport.requests.isEmpty { await Task.yield() }
        store.connectionDidChange(provider: .elevenlabs, account: nil)
        await request.value
        #expect(store.snapshots.isEmpty, "A response using the previous credential cannot repopulate the display")
        await store.refresh(trigger: .manual)
        #expect(store.snapshots.first?.windows.first?.usage?.value == 10)
    }

    @Test func absoluteCountersReachWidgetWithoutCredentialsOrFalseDailyActivity() throws {
        let snapshot = ProviderSnapshot(provider: .perplexity, status: .available,
            totals: [UsageTotal(kind: .creditsRemaining, value: 100)], updatedAt: TestDates.noon)
        let widget = WidgetSnapshotWriter.makeSnapshot(states: [ProviderState(provider: .perplexity, snapshot: snapshot)], enabledProviders: [.perplexity], generatedAt: TestDates.noon)
        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(widget))
        #expect(restored.providers.first?.totals == snapshot.totals)
        #expect(restored.providers.first?.tokensToday == nil)
        #expect(restored.providers.first?.creditsToday == nil)
        let json = String(decoding: try JSONEncoder().encode(widget), as: UTF8.self)
        #expect(!json.contains("session"))
        #expect(!json.contains("cookie"))
        #expect(!json.contains("credential"))
    }
}

private final class CountingConnectionKeys: APIKeyStoring, Sendable {
    private let reads = Mutex(0)
    var readCount: Int { reads.withLock { $0 } }
    func key(for provider: ProviderID, account: String?) throws -> String? { reads.withLock { $0 += 1 }; return nil }
    func setKey(_ key: String, for provider: ProviderID, account: String?) throws {}
    func removeKey(for provider: ProviderID, account: String?) throws {}
}
