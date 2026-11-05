import Foundation
import Testing
@testable import UsageNow

struct OverviewReadingTests {
    private let now = TestDates.noon
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

    @Test func periodUsesDaysAndAggregatesModelHistory() throws {
        let today = calendar.startOfDay(for: now)
        let records = [
            ActivityRecord(key: "a", timestamp: now, tokens: 100, model: "model-a"),
            ActivityRecord(key: "b", timestamp: today.addingTimeInterval(-3600), tokens: 200, model: "model-b"),
            ActivityRecord(key: "c", timestamp: today.addingTimeInterval(-8 * 86400), tokens: 300, model: "model-a"),
        ]
        var snapshot = Fixtures.snapshot(.codex, at: now)
        snapshot.activity.history = ActivityHistory(records: records, period: ActivityPeriod(now: now, calendar: calendar))
        let todayView = OverviewReading(snapshot: snapshot, period: .today, now: now, calendar: calendar)
        let week = OverviewReading(snapshot: snapshot, period: .week, now: now, calendar: calendar)
        let month = OverviewReading(snapshot: snapshot, period: .month, now: now, calendar: calendar)
        #expect(todayView.tokens == 100)
        #expect(week.tokens == 300)
        #expect(week.models.map(\.id) == ["model-b", "model-a"])
        #expect(month.tokens == 600)
        #expect(month.models.first?.totalTokens == 400)
        #expect(week.days.count == 7)
        #expect(!week.isCostComplete, "Unknown prices remain incomplete")
    }

    @Test func noHistoryDoesNotTurnTodaysCountIntoAMonthTotal() {
        let snapshot = Fixtures.snapshot(.gemini, at: now)
        #expect(OverviewReading(snapshot: snapshot, period: .today, now: now).tokens == 1_000_000)
        #expect(OverviewReading(snapshot: snapshot, period: .month, now: now).tokens == nil)
        #expect(!OverviewReading(snapshot: snapshot, period: .week, now: now).hasActivity)
    }

    @Test func creditsNeverBecomeTokensAndFutureDaysAreExcluded() {
        var snapshot = Fixtures.snapshot(.kiro, at: now)
        snapshot.activity.history = ActivityHistory(credits: [(now, Decimal(12)), (now.addingTimeInterval(86400), Decimal(99))],
            period: ActivityPeriod(now: now.addingTimeInterval(86400), calendar: calendar))
        let result = OverviewReading(snapshot: snapshot, period: .week, now: now, calendar: calendar)
        #expect(result.tokens == nil)
        #expect(result.credits == 12)
        #expect(result.requests == 1)
    }

    @Test func yesterdayCachedActivityIsNotTodaysActivity() {
        let snapshot = Fixtures.snapshot(.codex, at: now.addingTimeInterval(-86400))
        #expect(!OverviewReading(snapshot: snapshot, period: .today, now: now, calendar: calendar).hasActivity)
    }
}
