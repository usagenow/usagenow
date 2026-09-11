import Foundation
import Testing
@testable import UsageNow

struct MockProviderTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Friday, 11 September 2026, 10:00 UTC.
    private let reference = Date(timeIntervalSince1970: 1_789_120_800)

    @Test func normalCodexSnapshot() throws {
        let now = reference
        let provider = MockCodexProvider(referenceDate: reference, calendar: calendar, now: { now })
        let snapshot = try provider.snapshot()

        #expect(snapshot.status == .available)
        #expect(snapshot.window(.fiveHour)?.usage?.displayValue == 74)
        #expect(snapshot.window(.weekly)?.usage?.displayValue == 52)
        #expect(snapshot.window(.fiveHour)?.resetsAt == reference.addingTimeInterval(84 * 60))
        // Next Monday 09:00 UTC.
        #expect(snapshot.window(.weekly)?.resetsAt == Date(timeIntervalSince1970: 1_789_376_400))
        #expect(snapshot.activity.tokensToday == 12_800_000)
        #expect(snapshot.activity.requestsToday == 47)
    }

    @Test func fiveHourResetRollsForward() throws {
        let now = reference.addingTimeInterval(2 * 3600)
        let provider = MockClaudeProvider(referenceDate: reference, calendar: calendar, now: { now })
        let snapshot = try provider.snapshot()
        // First reset at +3h08m hasn't passed yet.
        #expect(snapshot.window(.fiveHour)?.resetsAt == reference.addingTimeInterval(188 * 60))

        let later = reference.addingTimeInterval(4 * 3600)
        let rolled = try MockClaudeProvider(referenceDate: reference, calendar: calendar, now: { later }).snapshot()
        #expect(rolled.window(.fiveHour)?.resetsAt == reference.addingTimeInterval(188 * 60 + 5 * 3600))
    }

    @Test func statusScenarios() throws {
        #expect(try MockCodexProvider(scenario: .notInstalled).snapshot().status == .notInstalled)
        #expect(try MockCodexProvider(scenario: .notAuthenticated).snapshot().status == .notAuthenticated)

        // Signed in with local activity, but no quota.
        let unavailable = try MockClaudeProvider(scenario: .unavailable).snapshot()
        #expect(unavailable.status == .available)
        #expect(unavailable.windows.isEmpty)
        #expect(unavailable.capabilities.contains(.tokenActivity))
        #expect(!unavailable.capabilities.contains(.quota))
    }

    @Test func failingScenarioThrows() async {
        let provider = MockCodexProvider(scenario: .failing, latency: .zero)
        await #expect(throws: ProviderError.self) {
            try await provider.fetchSnapshot(trigger: .automatic)
        }
    }
}
