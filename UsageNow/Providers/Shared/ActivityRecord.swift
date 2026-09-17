import Foundation

/// One model response observed in a local session file. Holds counts and
/// identifiers only — never prompt, response, or tool content.
struct ActivityRecord: Sendable, Equatable {
    /// Identifies the response, so copies (resumed or forked sessions,
    /// repeated streaming records) are counted once.
    var key: String
    var timestamp: Date
    var tokens: Int64
    var model: String?
    /// Tokens split the way providers charge for them, when the tool records
    /// the split. Needed for a cost estimate: cached tokens cost a fraction
    /// of fresh ones, and output costs several times more.
    var breakdown: TokenBreakdown? = nil

    /// Everything billed as input: fresh tokens plus cache writes and reads.
    var inputTokens: Int64? {
        guard let breakdown else { return nil }
        return breakdown.input + breakdown.cacheWrite + breakdown.cacheRead
    }

    var outputTokens: Int64? { breakdown?.output }
}

/// Local activity aggregated from session records.
struct ActivitySummary: Sendable, Equatable {
    var tokens: Int64 = 0
    var requests: Int64 = 0
    var latestModel: String?
    var latestModelAt: Date?
    /// Activity per model, most active first. Records without a model count
    /// toward the totals only.
    var models: [ModelActivity] = []
    /// What this activity would have cost at list prices, in USD, summed over
    /// the models UsageNow has a price for. `nil` when it has none of them.
    var estimatedCost: Decimal?
    /// False when some activity is missing from `estimatedCost`, because a
    /// model has no published price or a tool recorded no token split. True
    /// when there was nothing to price.
    var isCostComplete = true

    /// Sums records at or after `since`, counting each key once.
    init(records: some Sequence<ActivityRecord>, since: Date, prices: ModelPriceTable = .bundled) {
        var seen = Set<String>()
        var byModel: [String: ModelActivity] = [:]
        var breakdowns: [String: TokenBreakdown] = [:]
        var unpricedTokens: Int64 = 0

        for record in records where record.timestamp >= since {
            guard seen.insert(record.key).inserted else { continue }
            let tokens = max(0, record.tokens)
            self.tokens += tokens
            requests += 1
            guard let model = record.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else {
                unpricedTokens += tokens
                continue
            }

            if record.timestamp >= (latestModelAt ?? .distantPast) {
                latestModel = model
                latestModelAt = record.timestamp
            }
            var entry = byModel[model] ?? ModelActivity(modelID: model, totalTokens: 0, requests: 0)
            entry.totalTokens += tokens
            entry.requests += 1
            entry.inputTokens = Self.adding(record.inputTokens, to: entry.inputTokens)
            entry.outputTokens = Self.adding(record.outputTokens, to: entry.outputTokens)
            entry.lastUsedAt = Swift.max(entry.lastUsedAt ?? .distantPast, record.timestamp)
            byModel[model] = entry

            if let breakdown = record.breakdown {
                breakdowns[model] = (breakdowns[model] ?? TokenBreakdown()) + breakdown
            } else {
                unpricedTokens += tokens
            }
        }

        var total: Decimal?
        for (model, var entry) in byModel {
            guard let breakdown = breakdowns[model] else { continue }
            entry.estimatedCost = prices.cost(of: breakdown, model: model)
            byModel[model] = entry
            if let cost = entry.estimatedCost {
                total = (total ?? 0) + cost
            } else {
                unpricedTokens += breakdown.total
            }
        }

        estimatedCost = total
        // "Complete" means nothing was left out, which is also true of a day
        // with no activity at all — there the estimate is simply absent.
        isCostComplete = unpricedTokens == 0
        models = Array(byModel.values).sortedByActivity()
    }

    init() {}

    /// A split stays known once any record reports it.
    private static func adding(_ value: Int64?, to total: Int64?) -> Int64? {
        guard let value else { return total }
        return (total ?? 0) + max(0, value)
    }
}

enum SessionTimestamp {
    /// Parses ISO 8601 timestamps as written by the tools: "Z" or "+00:00"
    /// offsets, with or without fractional seconds of any precision.
    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
