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
}

/// Local activity aggregated from session records.
struct ActivitySummary: Sendable, Equatable {
    var tokens: Int64 = 0
    var requests: Int64 = 0
    var latestModel: String?
    var latestModelAt: Date?

    /// Sums records at or after `since`, counting each key once.
    init(records: some Sequence<ActivityRecord>, since: Date) {
        var seen = Set<String>()
        for record in records where record.timestamp >= since {
            guard seen.insert(record.key).inserted else { continue }
            tokens += max(0, record.tokens)
            requests += 1
            if let model = record.model, record.timestamp >= (latestModelAt ?? .distantPast) {
                latestModel = model
                latestModelAt = record.timestamp
            }
        }
    }

    init() {}
}

enum SessionTimestamp {
    /// Parses ISO 8601 timestamps as written by the tools: "Z" or "+00:00"
    /// offsets, with or without fractional seconds of any precision.
    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
