import Foundation

/// The days local activity is read for: today and the days before it.
///
/// Readers parse records from `start` on, so the same pass serves today's
/// numbers and the history chart. Days follow the user's calendar, so a day
/// is midnight to midnight where they are.
struct ActivityPeriod: Sendable, Equatable {
    /// Days shown in the history, today included. Claude Code deletes
    /// transcripts after 30 days by default, so a longer range would show
    /// gaps that aren't real.
    static let historyDays = 30

    var calendar: Calendar
    /// Midnight at the start of today.
    var today: Date
    /// Midnight at the start of the first day in the history.
    var start: Date
    var dayCount: Int

    init(now: Date, calendar: Calendar, days: Int = ActivityPeriod.historyDays) {
        self.calendar = calendar
        dayCount = max(1, days)
        today = calendar.startOfDay(for: now)
        start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
    }

    /// Each day's midnight, oldest first. Walks the calendar rather than
    /// adding 24 hours, so days around a clock change stay days.
    var dayStarts: [Date] {
        (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func dayStart(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

/// Local activity per day over `ActivityPeriod`, for the popover's chart.
///
/// Like `LocalActivity`, this is what the tool recorded on this Mac — not
/// quota and not a bill.
struct ActivityHistory: Sendable, Equatable {
    /// What the chart's bars measure. Tokens where the tool records them;
    /// otherwise the tool's own meter.
    enum Metric: Sendable, Equatable {
        case tokens
        case credits
        case requests
    }

    struct Day: Sendable, Equatable, Identifiable {
        /// Midnight at the start of the day.
        var start: Date
        var tokens: Int64 = 0
        var requests: Int64 = 0
        var estimatedCost: Decimal?
        var isCostComplete = true
        var credits: Decimal?

        var id: Date { start }
    }

    var metric: Metric
    /// Every day in the period, oldest first, including days with no activity.
    var days: [Day]
    var tokens: Int64
    var requests: Int64
    /// What the period's tokens would have cost at published API prices, in
    /// USD. `nil` when nothing could be priced.
    var estimatedCost: Decimal?
    var isCostComplete: Bool
    var credits: Decimal?
    /// The model with the most tokens over the period.
    var topModel: String?

    /// True when any day has something to show.
    var hasActivity: Bool {
        days.contains { $0.tokens > 0 || $0.requests > 0 || ($0.credits ?? 0) > 0 }
    }

    /// The bar height for `day`, in the chart's metric.
    func value(of day: Day) -> Double {
        switch metric {
        case .tokens: Double(day.tokens)
        case .credits: NSDecimalNumber(decimal: day.credits ?? 0).doubleValue
        case .requests: Double(day.requests)
        }
    }
}

extension ActivityHistory {
    /// Token history from model responses, priced per day the same way as
    /// today's estimate.
    init(records: [ActivityRecord], period: ActivityPeriod, prices: ModelPriceTable = .bundled) {
        let inPeriod = records.filter { $0.timestamp >= period.start }
        let byDay = Dictionary(grouping: inPeriod) { period.dayStart(for: $0.timestamp) }
        let days = period.dayStarts.map { start in
            let summary = ActivitySummary(records: byDay[start] ?? [], since: start, prices: prices)
            return Day(
                start: start,
                tokens: summary.tokens,
                requests: summary.requests,
                estimatedCost: summary.estimatedCost,
                isCostComplete: summary.isCostComplete
            )
        }
        let total = ActivitySummary(records: inPeriod, since: period.start, prices: prices)
        self.init(
            metric: .tokens,
            days: days,
            tokens: total.tokens,
            requests: total.requests,
            estimatedCost: total.estimatedCost,
            isCostComplete: total.isCostComplete,
            credits: nil,
            topModel: total.models.first?.modelID
        )
    }

    /// Credit history for tools that meter in credits and record no tokens.
    init(credits entries: [(date: Date, credits: Decimal)], period: ActivityPeriod) {
        var byDay: [Date: (credits: Decimal, requests: Int64)] = [:]
        for entry in entries where entry.date >= period.start {
            let start = period.dayStart(for: entry.date)
            byDay[start, default: (0, 0)].credits += entry.credits
            byDay[start, default: (0, 0)].requests += 1
        }
        let days = period.dayStarts.map { start in
            Day(start: start, requests: byDay[start]?.requests ?? 0, credits: byDay[start]?.credits ?? 0)
        }
        self.init(
            metric: .credits,
            days: days,
            tokens: 0,
            requests: days.reduce(0) { $0 + $1.requests },
            estimatedCost: nil,
            isCostComplete: true,
            credits: days.reduce(Decimal.zero) { $0 + ($1.credits ?? 0) },
            topModel: nil
        )
    }

    /// Request history for tools that time each request but meter nothing
    /// per day.
    init(requests dates: [Date], period: ActivityPeriod) {
        var byDay: [Date: Int64] = [:]
        for date in dates where date >= period.start {
            byDay[period.dayStart(for: date), default: 0] += 1
        }
        let days = period.dayStarts.map { Day(start: $0, requests: byDay[$0] ?? 0) }
        self.init(
            metric: .requests,
            days: days,
            tokens: 0,
            requests: days.reduce(0) { $0 + $1.requests },
            estimatedCost: nil,
            isCostComplete: true,
            credits: nil,
            topModel: nil
        )
    }
}
