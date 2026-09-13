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
    /// Input-side and output tokens, when the tool records the split.
    var inputTokens: Int64? = nil
    var outputTokens: Int64? = nil
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

    /// Sums records at or after `since`, counting each key once.
    init(records: some Sequence<ActivityRecord>, since: Date) {
        var seen = Set<String>()
        var byModel: [String: ModelActivity] = [:]
        for record in records where record.timestamp >= since {
            guard seen.insert(record.key).inserted else { continue }
            let tokens = max(0, record.tokens)
            self.tokens += tokens
            requests += 1
            guard let model = record.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else { continue }

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
        }
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
