import Foundation
import Testing
@testable import UsageNow

struct RetryAfterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: ["120", " 120 ", "000120"])
    func secondsAreRespected(_ value: String) {
        #expect(RetryAfter.deadline(value, now: now) == now.addingTimeInterval(120))
    }

    @Test func zeroStillPreventsAnImmediateRetryLoop() {
        #expect(RetryAfter.deadline("0", now: now) == now.addingTimeInterval(1))
    }

    @Test(arguments: [nil, "", "-1", "0.5", "NaN", "inf", "tomorrow", "99999999999999999999999999999999999999", "Fri, 01 Jan 1999 00:00:00 GMT"] as [String?])
    func invalidOrMissingHeaderUsesFiveMinutes(_ value: String?) {
        #expect(RetryAfter.deadline(value, now: now) == now.addingTimeInterval(300))
    }

    @Test func httpDateFormsUseUTCNotTheUsersLocale() {
        let target = Date(timeIntervalSince1970: 1_800_000_300)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            #expect(RetryAfter.deadline(formatter.string(from: target), now: now) == target)
        }
    }
}

struct APIRequestCooldownTests {
    @Test func manualAndBackgroundClientsShareThePauseButOtherConnectionsDoNot() async throws {
        let clock = TestClock(TestDates.noon)
        let cooldown = APIRequestCooldown(now: { clock.now })
        let transport = CooldownTransport(status: 429, retryAfter: "120")
        let connection = ProviderCatalog.definition(for: .elevenlabs).apiKey!
        let first = APIKeyClient(connection: connection, transport: transport, cooldown: cooldown)
        let second = APIKeyClient(connection: connection, transport: transport, cooldown: cooldown)
        let deadline = clock.now.addingTimeInterval(120)
        await #expect(throws: APIKeyClient.Failure.rateLimited(until: deadline)) {
            try await first.get("/v1/user/subscription", key: "test-one")
        }
        await transport.setStatus(200)
        // Recreating a client or pressing Retry cannot bypass Retry-After.
        await #expect(throws: APIKeyClient.Failure.rateLimited(until: deadline)) {
            try await second.get("/v1/user/subscription", key: "test-one")
        }
        #expect(await transport.requests.count == 1)
        _ = try await second.get("/v1/user/subscription", key: "test-two")
        let other = APIKeyClient(connection: ProviderCatalog.definition(for: .copilot).apiKey!, transport: transport, cooldown: cooldown)
        _ = try await other.get("/copilot_internal/user", key: "test-one")
        #expect(await transport.requests.count == 3)
        clock.advance(by: 120)
        _ = try await second.get("/v1/user/subscription", key: "test-one")
        #expect(await transport.requests.count == 4)
    }

    @Test func equivalentCookieHeadersCannotBypassPause() async {
        let clock = TestClock(TestDates.noon)
        let transport = CooldownTransport(status: 429)
        let client = APIKeyClient(connection: ProviderCatalog.definition(for: .cursor).apiKey!, transport: transport,
                                  cooldown: APIRequestCooldown(now: { clock.now }))
        let failure = APIKeyClient.Failure.rateLimited(until: clock.now.addingTimeInterval(300))
        for cookie in ["WorkosCursorSessionToken=test", "analytics=ignored; WorkosCursorSessionToken=test"] {
            await #expect(throws: failure) { try await client.get("/api/usage-summary", key: cookie) }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func aLateResponseCannotShortenThePause() async {
        let clock = TestClock(TestDates.noon)
        let cooldown = APIRequestCooldown(now: { clock.now })
        let first = await cooldown.record(host: "api.example.invalid", credential: "test", retryAfter: "600")
        let second = await cooldown.record(host: "api.example.invalid", credential: "test", retryAfter: "1")
        #expect(first == second)
    }

    @Test func otherFailuresDoNotStartAPause() async throws {
        let transport = CooldownTransport(status: 503, retryAfter: "300")
        let client = APIKeyClient(connection: ProviderCatalog.definition(for: .elevenlabs).apiKey!, transport: transport,
                                  cooldown: APIRequestCooldown())
        await #expect(throws: APIKeyClient.Failure.unexpectedStatus(503)) { try await client.get("/v1/user/subscription", key: "test") }
        await transport.setStatus(200)
        _ = try await client.get("/v1/user/subscription", key: "test")
        #expect(await transport.requests.count == 2)
    }

    @Test @MainActor func rateLimitKeepsValuesAndTheirDateInTheStoreAndWidget() async throws {
        let old = TestDates.noon.addingTimeInterval(-60)
        let clock = TestClock(TestDates.noon)
        let good = Fixtures.snapshot(.elevenlabs, fiveHour: 40, weekly: 25, at: old)
        let provider = StubProvider(.elevenlabs, .success(good))
        let store = UsageStore(providers: [provider], now: { clock.now })
        await store.refresh()
        let deadline = clock.now.addingTimeInterval(300)
        await provider.setResult(.failure(APIKeyClient.Failure.rateLimited(until: deadline)))
        await store.refresh(trigger: .manual)
        let state = try #require(store.states.first)
        #expect(state.snapshot == good)
        #expect(state.failure?.retryAt == deadline)
        let widget = WidgetSnapshotWriter.makeSnapshot(states: [state], enabledProviders: [.elevenlabs], generatedAt: clock.now)
        guard case .providers(let readings) = widget.state else { Issue.record("Expected the last good reading"); return }
        #expect(readings.first?.updatedAt == good.dataDate)
        #expect(readings.first?.windows == good.windows)
        clock.advance(by: 300)
        var next = good
        next.updatedAt = clock.now
        await provider.setResult(.success(next))
        await store.refresh()
        #expect(store.states.first?.failure == nil)
        #expect(store.states.first?.snapshot?.updatedAt == clock.now)
    }

    @Test @MainActor func firstReadingCanBeRateLimitedWithoutInventingUsage() async {
        let until = TestDates.noon.addingTimeInterval(300)
        let store = UsageStore(providers: [StubProvider(.copilot, .failure(APIKeyClient.Failure.rateLimited(until: until)))])
        await store.refresh()
        #expect(store.states.first?.snapshot == nil)
        #expect(store.states.first?.isVisible == true)
        #expect(store.states.first?.failure?.retryAt == until)
    }
}

private actor CooldownTransport: HTTPTransport {
    private var status: Int
    private let retryAfter: String?
    private(set) var requests: [URLRequest] = []
    init(status: Int, retryAfter: String? = nil) { self.status = status; self.retryAfter = retryAfter }
    func setStatus(_ status: Int) { self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let headers = retryAfter.map { ["Retry-After": $0] }
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}
