import Foundation
import Testing
@testable import UsageNow

@MainActor
struct QuotaPaceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func pace(_ values: [Double] = [20, 30, 40], resetAfter: TimeInterval = 3_600) -> QuotaPace {
        QuotaPace(
            window: UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: values.last ?? 0), resetsAt: now.addingTimeInterval(resetAfter)),
            points: values.enumerated().map { offset, value in
                .init(date: now.addingTimeInterval(Double(offset - values.count + 1) * 600), used: UsagePercentage(percent: value)!)
            }
        )
    }

    private func snapshot(at date: Date, used: Double = 40, account: String? = nil) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .codex, status: .available,
            windows: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: used), resetsAt: now.addingTimeInterval(3_600))],
            updatedAt: date, account: account.map { AccountTag(id: $0, name: "Private name") }
        )
    }

    @Test func cautiouslyProjectsMeasuredUsageOnly() {
        #expect(pace().estimate(at: now) == .lastsUntilReset)
        #expect(pace([20, 45, 70]).estimate(at: now) == .exhaustsBeforeReset(now.addingTimeInterval(720)))
        #expect(pace([40, 40, 40]).estimate(at: now) == .lastsUntilReset)
        #expect(pace([90, 95, 100]).estimate(at: now) == nil)
    }

    @Test func hidesInsufficientStaleFutureAndExpiredReadings() {
        #expect(pace([20, 40]).estimate(at: now) == nil)
        #expect(pace().estimate(at: now.addingTimeInterval(601)) == nil)
        #expect(pace().estimate(at: now.addingTimeInterval(-1)) == nil)
        #expect(pace(resetAfter: 0).estimate(at: now) == nil)
        #expect(pace(resetAfter: 6 * 3_600).estimate(at: now) == nil)
        #expect(pace([20, 60, 99]).estimate(at: now.addingTimeInterval(60)) == nil)
    }

    @Test func hidesUnknownDurationCorrectionsAndGaps() {
        for kind in [UsageWindowKind.monthly, .allowance, .custom(minutes: 0), .custom(minutes: Int.max)] {
            var reading = pace()
            reading.window = UsageWindow(kind: kind, usage: reading.window.usage, resetsAt: reading.window.resetsAt)
            #expect(reading.estimate(at: now) == nil)
        }
        #expect(pace([30, 20, 40]).estimate(at: now) == nil)
        var reading = pace()
        reading.points[0] = .init(date: now.addingTimeInterval(-4_000), used: UsagePercentage(percent: 20)!)
        #expect(reading.estimate(at: now) == nil)
    }

    @Test func cachedValuesDoNotCreateSamplesAndCorrectionsResetTrend() {
        let history = QuotaHistory()
        for offset in [-1_200.0, -600, 0] {
            let date = now.addingTimeInterval(offset)
            _ = history.observe(snapshot(at: date), at: date)
        }
        var cached = snapshot(at: now.addingTimeInterval(120))
        cached.limitsUpdatedAt = now
        #expect(history.observe(cached, at: now.addingTimeInterval(120)).first?.points.count == 3)
        cached.windows[0].usage = UsagePercentage(percent: 42)
        #expect(history.observe(cached, at: now.addingTimeInterval(120)).first?.points.count == 1)
    }

    @Test func resetDropAndOvernightGapStartNewHistory() {
        let history = QuotaHistory()
        _ = history.observe(snapshot(at: now), at: now)
        #expect(history.observe(snapshot(at: now.addingTimeInterval(60), used: 10), at: now.addingTimeInterval(60)).first?.points.count == 1)
        let later = now.addingTimeInterval(2_200)
        #expect(history.observe(snapshot(at: later), at: later).first?.points.count == 1)
        var reset = snapshot(at: later.addingTimeInterval(60), used: 0)
        reset.windows[0].resetsAt = later.addingTimeInterval(5 * 3_600)
        #expect(history.observe(reset, at: later.addingTimeInterval(60)).first?.points.count == 1)
    }

    @Test func unavailableAndStaleQuotaNeverProducesForecast() {
        let history = QuotaHistory()
        var reading = snapshot(at: now)
        reading.quotaUnavailableReason = .signInExpired
        #expect(history.observe(reading, at: now).isEmpty)
        #expect(history.observe(snapshot(at: now), at: now.addingTimeInterval(601)).isEmpty)
        #expect(history.observe(snapshot(at: now.addingTimeInterval(1)), at: now).isEmpty)
    }

    @Test func persistsOnlyQuotaAndIsolatesAccounts() throws {
        let suite = "QuotaPaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = QuotaHistory(defaults: defaults)
        _ = history.observe(snapshot(at: now, account: "work"), at: now)
        let reloaded = QuotaHistory(defaults: defaults)
        let next = now.addingTimeInterval(600)
        #expect(reloaded.observe(snapshot(at: next, account: "work"), at: next).first?.points.count == 2)
        #expect(reloaded.observe(snapshot(at: next, account: "personal"), at: next).first?.points.count == 1)
        let data = try #require(defaults.data(forKey: "quotaObservations.v1"))
        #expect(!String(decoding: data, as: UTF8.self).contains("Private name"))
        reloaded.retain([SourceKey(provider: .codex, account: "personal")])
        #expect(reloaded.observe(snapshot(at: next, account: "work"), at: next).first?.points.count == 1)
        reloaded.remove(SourceKey(provider: .codex, account: "personal"))
        #expect(reloaded.observe(snapshot(at: next, account: "personal"), at: next).first?.points.count == 1)
    }

    @Test func historyIsBounded() {
        let history = QuotaHistory()
        var count = 0
        for minute in -180...0 {
            let date = now.addingTimeInterval(Double(minute) * 60)
            count = history.observe(snapshot(at: date), at: date).first?.points.count ?? 0
        }
        #expect(count == QuotaPace.maximumPoints)
    }
}
