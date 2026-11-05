import Foundation
import Testing
@testable import UsageNow

struct MiniMaxProviderTests {
    private func body(_ fields: String = "") -> Data {
        Data("""
        {"base_resp":{"status_code":0},"model_remains":[{
        "model_name":"MiniMax-M*","start_time":1793793600000,"end_time":1793811600000,
        "weekly_start_time":1793613600000,"weekly_end_time":1794218400000,
        "current_interval_total_count":1000,"current_interval_usage_count":250,
        "current_weekly_total_count":5000,"current_weekly_usage_count":3000\(fields)
        }]}
        """.utf8)
    }

    @Test func legacyUsageCountIsRemainingAndWindowsComeFromReportedDuration() throws {
        let reading = try MiniMaxUsage.parse(body())
        #expect(reading.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(reading.windows.first?.usage?.remainingDisplayValue == 25)
        #expect(reading.windows.last?.usage?.remainingDisplayValue == 60)
        #expect(reading.planName == nil, "A tier is not inferred from the allowance")
        #expect(reading.balance == nil)
    }

    @Test func explicitRemainingPercentageDisambiguatesNewConsumedCounters() throws {
        let reading = try MiniMaxUsage.parse(body(",\"current_interval_remaining_percent\":75"))
        #expect(reading.windows.first?.usage?.remainingDisplayValue == 75)
    }

    @Test func contradictoryCountersAndBoostedAllowancesStayUnknown() throws {
        let reading = try MiniMaxUsage.parse(body(",\"current_interval_remaining_percent\":40,\"weekly_boost_permille\":1500"))
        #expect(reading.windows.allSatisfy { $0.usage == nil })
        #expect(reading.quotaUnavailableReason == .temporarilyUnavailable)
    }

    @Test func unlimitedWeeklyWindowIsOmittedRatherThanDisplayedAsEmpty() throws {
        let reading = try MiniMaxUsage.parse(body(",\"current_weekly_status\":3"))
        #expect(reading.windows.count == 1)
        #expect(reading.windows.first?.kind == .fiveHour)
    }

    @Test func missingQuotaAndAuthenticationFailuresAreNotZeroes() {
        #expect(throws: APIKeyClient.Failure.unreadableResponse) { try MiniMaxUsage.parse(Data("{}".utf8)) }
        #expect(throws: APIKeyClient.Failure.unreadableResponse) { try MiniMaxUsage.parse(Data(#"{"model_remains":[]}"#.utf8)) }
        #expect(throws: APIKeyClient.Failure.rejectedKey) { try MiniMaxUsage.parse(Data(#"{"base_resp":{"status_code":1004}}"#.utf8)) }
    }

    @Test func offByDefaultAndNoKeyDoesNotTouchTheNetwork() async throws {
        let transport = StubTransport(status: 200, body: String(decoding: body(), as: UTF8.self))
        let provider = APIKeyProvider.miniMax(keys: KeychainAPIKeyStore(store: InMemorySecureStore()), transport: transport)
        #expect(try await provider.fetchSnapshot(trigger: .automatic).status == .notInstalled)
        #expect(await transport.requests.isEmpty)
        await MainActor.run { #expect(!ProviderPreferences.defaultEnabled.contains(.minimax)) }
    }

    @Test func credentialCheckIsReadOnlyOnTheSingleOfficialHost() async throws {
        let transport = StubTransport(status: 200, body: String(decoding: body(), as: UTF8.self))
        let keys = KeychainAPIKeyStore(store: InMemorySecureStore())
        let provider = APIKeyProvider.miniMax(keys: keys, transport: transport)
        #expect(try await provider.verifyCredential("subscription-fixture") == "subscription-fixture")
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://www.minimax.io/v1/token_plan/remains")
        #expect(!keys.hasKey(for: .minimax))
    }
}
