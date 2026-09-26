import Foundation
import Testing

@testable import UsageNow

struct ActivityHistoryTests {
    private let noon = TestDates.noon
    private let day: TimeInterval = 86_400
    private var period: ActivityPeriod { ActivityPeriod(now: noon, calendar: TestDates.utc) }

    private let prices = try! ModelPriceTable(
        data: Data(
            """
            {"generated":"2026-09-26","source":"test","unit":"USD per million tokens",
             "models":{"claude-opus-5":{"input":"5","output":"25","cacheWrite":"6.25","cacheRead":"0.5"}}}
            """.utf8
        )
    )

    private func record(_ key: String, _ date: Date, input: Int64, output: Int64, model: String? = "claude-opus-5") -> ActivityRecord {
        ActivityRecord(
            key: key,
            timestamp: date,
            tokens: input + output,
            model: model,
            breakdown: TokenBreakdown(input: input, output: output)
        )
    }

    @Test func periodCoversThirtyDaysEndingToday() {
        let days = period.dayStarts
        #expect(days.count == 30)
        #expect(days.last == TestDates.utc.startOfDay(for: noon))
        #expect(days.first == period.start)
        #expect(period.start == TestDates.utc.startOfDay(for: noon.addingTimeInterval(-29 * day)))
    }

    @Test func recordsLandOnTheirOwnDayAndEmptyDaysStayInTheChart() {
        let history = ActivityHistory(records: [
            record("a", noon, input: 1_000_000, output: 0),
            record("b", noon.addingTimeInterval(-day), input: 2_000_000, output: 0),
            record("c", noon.addingTimeInterval(-day - 3600), input: 0, output: 1_000_000),
        ], period: period, prices: prices)

        #expect(history.metric == .tokens)
        #expect(history.days.count == 30)
        #expect(history.days[29].tokens == 1_000_000)
        #expect(history.days[29].estimatedCost == 5)
        #expect(history.days[28].tokens == 3_000_000)
        #expect(history.days[28].requests == 2)
        #expect(history.days[28].estimatedCost == 35)
        #expect(history.days[0].tokens == 0)
        #expect(history.days[0].estimatedCost == nil)

        #expect(history.tokens == 4_000_000)
        #expect(history.requests == 3)
        #expect(history.estimatedCost == 40)
        #expect(history.isCostComplete)
        #expect(history.topModel == "claude-opus-5")
        #expect(history.hasActivity)
    }

    @Test func recordsBeforeThePeriodAreLeftOut() {
        let history = ActivityHistory(records: [
            record("old", noon.addingTimeInterval(-40 * day), input: 9_000_000, output: 0),
        ], period: period, prices: prices)
        #expect(history.tokens == 0)
        #expect(!history.hasActivity)
        #expect(history.topModel == nil)
    }

    /// A day with an unpriced model says its estimate is a floor, and so does the total.
    @Test func unpricedModelsMarkTheirDayPartial() {
        let history = ActivityHistory(records: [
            record("a", noon, input: 1_000_000, output: 0),
            record("b", noon, input: 1_000_000, output: 0, model: "some-local-model"),
            record("c", noon.addingTimeInterval(-day), input: 1_000_000, output: 0),
        ], period: period, prices: prices)
        #expect(history.days[29].isCostComplete == false)
        #expect(history.days[28].isCostComplete)
        #expect(history.isCostComplete == false)
        #expect(history.estimatedCost == 10)
    }

    /// A copied response counts once, the same as in today's totals.
    @Test func duplicatesCountOnce() {
        let copy = record("same", noon, input: 500, output: 500)
        let history = ActivityHistory(records: [copy, copy], period: period, prices: prices)
        #expect(history.days[29].tokens == 1_000)
        #expect(history.tokens == 1_000)
    }

    @Test func creditHistoryCountsTurnsAndCredits() {
        let history = ActivityHistory(credits: [
            (noon, Decimal(string: "1.5")!),
            (noon.addingTimeInterval(-60), Decimal(string: "0.25")!),
            (noon.addingTimeInterval(-2 * day), 3),
        ], period: period)
        #expect(history.metric == .credits)
        #expect(history.days[29].credits == Decimal(string: "1.75"))
        #expect(history.days[29].requests == 2)
        #expect(history.days[27].credits == 3)
        #expect(history.days[28].credits == 0)
        #expect(history.credits == Decimal(string: "4.75"))
        #expect(history.value(of: history.days[29]) == 1.75)
    }

    @Test func requestHistoryCountsRequests() {
        let history = ActivityHistory(requests: [noon, noon, noon.addingTimeInterval(-day)], period: period)
        #expect(history.metric == .requests)
        #expect(history.days[29].requests == 2)
        #expect(history.requests == 3)
        #expect(history.value(of: history.days[28]) == 1)
    }

    /// Days are calendar days where the user is, not 24-hour blocks: the day
    /// clocks go forward has 23 hours and still gets one bar.
    @Test func daysFollowTheCalendarAcrossAClockChange() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // Clocks went forward on 29 March 2026.
        let now = try #require(berlin.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 12)))
        let period = ActivityPeriod(now: now, calendar: berlin)
        let starts = period.dayStarts
        #expect(starts.count == 30)
        #expect(Set(starts).count == 30)
        #expect(starts.allSatisfy { berlin.component(.hour, from: $0) == 0 })
    }
}
