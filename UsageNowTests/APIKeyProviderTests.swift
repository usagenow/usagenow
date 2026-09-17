import Foundation
import Testing

@testable import UsageNow

/// Answers every request from a fixed URL, to stand in for a redirect.
private actor RedirectedTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let elsewhere = URL(string: "https://collector.example.invalid/steal")!
        return (Data("{}".utf8), HTTPURLResponse(url: elsewhere, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class MemoryKeys: APIKeyStoring, @unchecked Sendable {
    private var keys: [ProviderID: String] = [:]
    init(_ keys: [ProviderID: String] = [:]) { self.keys = keys }
    func key(for provider: ProviderID) throws -> String? { keys[provider] }
    func setKey(_ key: String, for provider: ProviderID) throws { keys[provider] = key }
    func removeKey(for provider: ProviderID) throws { keys[provider] = nil }
}

struct APIKeyClientTests {
    private let deepSeek = ProviderCatalog.definition(for: .deepseek).apiKey!

    @Test func sendsTheKeyOnlyToTheProvidersHostOverHTTPS() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        _ = try await APIKeyClient(connection: deepSeek, transport: transport).get("/user/balance", key: "sk-test")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/user/balance")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test func aRejectedKeyIsItsOwnFailure() async {
        for status in [401, 403] {
            let client = APIKeyClient(connection: deepSeek, transport: StubTransport(status: status, body: ""))
            await #expect(throws: APIKeyClient.Failure.rejectedKey) { try await client.get("/user/balance", key: "sk-bad") }
        }
    }

    @Test func otherStatusesAreUnexpected() async {
        let client = APIKeyClient(connection: deepSeek, transport: StubTransport(status: 503, body: ""))
        await #expect(throws: APIKeyClient.Failure.unexpectedStatus(503)) { try await client.get("/user/balance", key: "sk") }
    }

    /// A redirect is what could carry the key's header somewhere else.
    @Test func refusesAnAnswerFromAnotherHost() async {
        let client = APIKeyClient(connection: deepSeek, transport: RedirectedTransport())
        await #expect(throws: APIKeyClient.Failure.refusedDestination) { try await client.get("/user/balance", key: "sk") }
    }

    @Test func everyKeyProviderNamesItsHost() {
        #expect(ProviderCatalog.definition(for: .deepseek).apiKey?.host == "api.deepseek.com")
        #expect(ProviderCatalog.definition(for: .kimi).apiKey?.host == "api.moonshot.ai")
        #expect(ProviderCatalog.definition(for: .openrouter).apiKey?.host == "openrouter.ai")
        // Tools read on this Mac never take a key.
        for id in [ProviderID.codex, .claudeCode, .gemini, .antigravity, .kiro, .warp] {
            #expect(ProviderCatalog.definition(for: id).apiKey == nil)
        }
    }
}

struct APIKeyResponseParsingTests {
    @Test func deepSeekPrefersDollarsAndKeepsTheCurrency() throws {
        let body = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"},{"currency":"USD","total_balance":"4.25","granted_balance":"0.00","topped_up_balance":"4.25"}]}"#
        let balance = try #require(try DeepSeekBalance.parse(Data(body.utf8)).balance)
        #expect(balance.currency == "USD")
        #expect(balance.remaining == Decimal(string: "4.25"))
        #expect(balance.canMakeRequests)
    }

    @Test func deepSeekInYuanStaysInYuan() throws {
        let body = #"{"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"}]}"#
        let balance = try #require(try DeepSeekBalance.parse(Data(body.utf8)).balance)
        #expect(balance.currency == "CNY")
        #expect(balance.remaining == 0)
        #expect(!balance.canMakeRequests)
    }

    @Test func kimiReadsTheAvailableBalance() throws {
        let body = #"{"code":0,"data":{"available_balance":49.58894,"voucher_balance":46.58893,"cash_balance":3.00001},"scode":"0x0","status":true}"#
        let balance = try #require(try KimiBalance.parse(Data(body.utf8)).balance)
        #expect(balance.remaining == Decimal(string: "49.58894"))
        #expect(balance.currency == "USD")
        #expect(balance.canMakeRequests)
    }

    @Test func openRouterReadsSpendingAndAMonthlyKeyLimit() throws {
        let body = #"{"data":{"label":"sk-or-v1-abc...","limit":20,"limit_remaining":15,"limit_reset":"monthly","usage":5,"usage_daily":0.75,"usage_weekly":2,"usage_monthly":5,"is_free_tier":false}}"#
        let reading = try OpenRouterKey.parse(Data(body.utf8))
        #expect(reading.balance?.spentToday == Decimal(string: "0.75"))
        #expect(reading.balance?.spentThisMonth == 5)
        #expect(reading.balance?.remaining == 15)
        #expect(reading.windows.map(\.kind) == [.monthly])
        #expect(reading.windows.first?.usage == UsagePercentage(used: 5, limit: 20))
    }

    /// No limit on the key means no window and no "left" amount to invent.
    @Test func openRouterWithoutALimitShowsSpendingOnly() throws {
        let body = #"{"data":{"limit":null,"limit_remaining":null,"limit_reset":null,"usage":12,"usage_daily":1,"usage_monthly":12}}"#
        let reading = try OpenRouterKey.parse(Data(body.utf8))
        #expect(reading.windows.isEmpty)
        #expect(reading.balance?.remaining == nil)
        #expect(reading.balance?.spentThisMonth == 12)
        #expect(reading.balance?.canMakeRequests == true)
    }

    @Test func unreadableAnswersThrow() {
        for body in ["", "{}", #"{"balance_infos":[]}"#, "not json"] {
            #expect(throws: APIKeyClient.Failure.unreadableResponse) { try DeepSeekBalance.parse(Data(body.utf8)) }
        }
        #expect(throws: APIKeyClient.Failure.unreadableResponse) { try KimiBalance.parse(Data(#"{"status":false}"#.utf8)) }
    }
}

struct APIKeyProviderTests {
    private let noon = TestDates.noon

    @Test func withoutAKeyTheProviderStaysOutOfSight() async throws {
        let transport = StubTransport(status: 200, body: "{}")
        let snapshot = try await APIKeyProvider.deepSeek(keys: MemoryKeys(), transport: transport).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notInstalled)
        #expect(await transport.requests.isEmpty, "No key, no request")
    }

    @Test func aReadingBecomesABalance() async throws {
        let body = #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12.40"}]}"#
        let snapshot = try await APIKeyProvider.deepSeek(keys: MemoryKeys([.deepseek: "sk-1"]), transport: StubTransport(status: 200, body: body))
            .fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.balance?.remaining == Decimal(string: "12.40"))
    }

    @Test func aRejectedKeyShowsAsSignedOut() async throws {
        let snapshot = try await APIKeyProvider.kimi(keys: MemoryKeys([.kimi: "sk-revoked"]), transport: StubTransport(status: 401, body: ""))
            .fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notAuthenticated)
    }

    /// The store keeps the last reading and reports the failed refresh.
    @Test func anOutageIsAFailedRefreshNotAnEmptyBalance() async {
        let provider = APIKeyProvider.openRouter(keys: MemoryKeys([.openrouter: "sk-or"]), transport: StubTransport(status: 502, body: ""))
        await #expect(throws: APIKeyClient.Failure.unexpectedStatus(502)) { try await provider.fetchSnapshot(trigger: .automatic) }
    }
}

struct KeychainAPIKeyStoreTests {
    @Test func savesTrimmedKeysPerProviderAndRemovesEmptyOnes() throws {
        let store = KeychainAPIKeyStore(store: InMemorySecureStore())
        try store.setKey("  sk-abc\n", for: .deepseek)
        #expect(try store.key(for: .deepseek) == "sk-abc")
        #expect(try store.key(for: .kimi) == nil)
        #expect(store.hasKey(for: .deepseek))

        try store.setKey("   ", for: .deepseek)
        #expect(!store.hasKey(for: .deepseek))
    }
}
