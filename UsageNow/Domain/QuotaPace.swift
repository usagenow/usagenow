import Foundation

/// Observations of reported quota, never reconstructed from token activity.
struct QuotaPace: Codable, Equatable, Sendable, Identifiable {
    struct Point: Codable, Equatable, Sendable, Identifiable {
        let date: Date
        let used: UsagePercentage
        var id: Date { date }
    }

    var window: UsageWindow
    var points: [Point]
    var id: String { window.id }

    enum Estimate: Equatable, Sendable {
        case lastsUntilReset
        case exhaustsBeforeReset(Date)
    }

    static let minimumSpan: TimeInterval = 15 * 60
    static let maximumGap: TimeInterval = 35 * 60
    static let maximumPoints = 120

    /// Nominal monthly lengths must not be mistaken for observed windows.
    static func duration(of kind: UsageWindowKind) -> TimeInterval? {
        switch kind {
        case .fiveHour: return 5 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        case .custom(let minutes) where minutes > 0 && minutes <= 31 * 24 * 60:
            return TimeInterval(minutes) * 60
        case .monthly, .allowance, .custom: return nil
        }
    }

    /// A recent measured trend, not a promise about future usage.
    func estimate(at date: Date) -> Estimate? {
        guard let duration = Self.duration(of: window.kind), let reset = window.resetsAt,
              reset > date, reset.timeIntervalSince(date) <= duration + 60,
              points.count >= 3, let first = points.first, let last = points.last,
              last.date <= date, date.timeIntervalSince(last.date) <= ProviderSnapshot.staleThreshold,
              first.date >= reset.addingTimeInterval(-duration - 60),
              last.date.timeIntervalSince(first.date) >= Self.minimumSpan,
              last.used.value < 100 else { return nil }
        for (before, after) in zip(points, points.dropFirst()) {
            guard after.date > before.date,
                  after.date.timeIntervalSince(before.date) <= Self.maximumGap,
                  after.used >= before.used else { return nil }
        }
        let rate = (last.used.value - first.used.value) / last.date.timeIntervalSince(first.date)
        guard rate.isFinite, rate >= 0 else { return nil }
        guard rate > 0 else { return .lastsUntilReset }
        let exhaustion = last.date.addingTimeInterval((100 - last.used.value) / rate)
        // A past estimate isn't evidence that the provider actually ran out.
        guard exhaustion > date else { return nil }
        return exhaustion < reset ? .exhaustsBeforeReset(exhaustion) : .lastsUntilReset
    }
}
