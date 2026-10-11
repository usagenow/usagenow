import Foundation

/// The plan and limits Windsurf last received, as it caches them for itself.
///
/// Windsurf keeps them under one key of its settings database,
/// `windsurf.settings.cachedPlanInfo`, as JSON. Only that key is selected;
/// the same table holds Windsurf's sign-in, which is never read. Windsurf
/// refreshes the cache while it runs, so between runs this is the last
/// reading it took.
struct WindsurfPlanReader: Sendable {
    static let key = "windsurf.settings.cachedPlanInfo"

    /// The cache's shape. Newer versions report daily and weekly quotas as
    /// percentages left; older ones count prompt credits and flow actions
    /// per billing cycle. Either may be missing.
    struct PlanInfo: Decodable, Sendable, Equatable {
        var planName: String?
        /// The billing cycle, in milliseconds since 1970.
        var startTimestamp: Int64?
        var endTimestamp: Int64?
        var usage: Usage?
        var quotaUsage: QuotaUsage?

        struct Usage: Decodable, Sendable, Equatable {
            var messages: Int64?
            var usedMessages: Int64?
            var remainingMessages: Int64?
            var flowActions: Int64?
            var usedFlowActions: Int64?
            var remainingFlowActions: Int64?
        }

        struct QuotaUsage: Decodable, Sendable, Equatable {
            var dailyRemainingPercent: Double?
            var weeklyRemainingPercent: Double?
            var dailyResetAtUnix: Int64?
            var weeklyResetAtUnix: Int64?
        }
    }

    /// The cached plan, or `nil` when Windsurf hasn't cached one.
    func plan(database: URL) throws -> PlanInfo? {
        let connection = try ReadOnlyDatabase(url: database)
        guard try connection.hasTable("ItemTable") else { return nil }
        let values = try connection.rows("SELECT value FROM ItemTable WHERE key = ? LIMIT 1", bind: [Self.key]) { row in
            row.data(0)
        }
        guard let data = values.first ?? nil else { return nil }
        return try? JSONDecoder().decode(PlanInfo.self, from: data)
    }
}

extension WindsurfPlanReader.PlanInfo {
    /// The limits to show: the daily and weekly quotas when Windsurf reports
    /// them, otherwise prompt credits and flow actions for the billing cycle.
    /// A count without its total is left out rather than guessed.
    var windows: [UsageWindow] {
        if let quotaUsage, quotaUsage.dailyRemainingPercent != nil || quotaUsage.weeklyRemainingPercent != nil {
            return [
                quotaUsage.dailyRemainingPercent.map { remaining in
                    UsageWindow(
                        kind: .custom(minutes: 24 * 60),
                        usage: UsagePercentage(percent: 100 - remaining),
                        resetsAt: quotaUsage.dailyResetAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                },
                quotaUsage.weeklyRemainingPercent.map { remaining in
                    UsageWindow(
                        kind: .weekly,
                        usage: UsagePercentage(percent: 100 - remaining),
                        resetsAt: quotaUsage.weeklyResetAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                },
            ].compactMap(\.self)
        }

        let cycleEnd = endTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        let credits = Self.share(total: usage?.messages, used: usage?.usedMessages, remaining: usage?.remainingMessages)
        let actions = Self.share(total: usage?.flowActions, used: usage?.usedFlowActions, remaining: usage?.remainingFlowActions)
        return [
            credits.map { UsageWindow(kind: .monthly, usage: $0, resetsAt: cycleEnd) },
            actions.map { UsageWindow(kind: .monthly, scope: "Flow actions", usage: $0, resetsAt: cycleEnd) },
        ].compactMap(\.self)
    }

    private static func share(total: Int64?, used: Int64?, remaining: Int64?) -> UsagePercentage? {
        guard let total, total > 0 else { return nil }
        guard let spent = used ?? remaining.map({ total - min(max($0, 0), total) }) else { return nil }
        return UsagePercentage(fraction: Double(min(max(spent, 0), total)) / Double(total))
    }
}
