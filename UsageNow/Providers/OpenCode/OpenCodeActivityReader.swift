import Foundation

/// OpenCode activity, read from its local database.
///
/// Each answer from a model is an assistant message whose JSON records the
/// model and its token split. SQLite extracts those numbers, and only those
/// leave the database: the message JSON also holds the reply's text in newer
/// versions, so it's never selected whole. Prompts live in other tables that
/// aren't read at all.
///
/// OpenCode has stored messages two ways: the `message` table, and the newer
/// `session_message`. Both may exist; the first one with activity in the
/// period is read, so a message recorded in both is never counted twice.
struct OpenCodeActivityReader: Sendable {
    struct Result: Sendable, Equatable {
        /// Today's activity.
        var activity: ActivitySummary
        var history: ActivityHistory
    }

    private struct Source {
        var table: String
        var model: String
        /// Selects assistant messages.
        var filter: String
    }

    private static let sources = [
        Source(table: "message", model: "$.modelID", filter: "json_extract(data, '$.role') = 'assistant'"),
        Source(table: "session_message", model: "$.model.id", filter: "type = 'assistant'"),
    ]

    func activity(database: URL, period: ActivityPeriod) throws -> Result {
        let connection = try ReadOnlyDatabase(url: database)
        var records: [ActivityRecord] = []
        for source in Self.sources where try connection.hasTable(source.table) {
            records = try Self.records(from: source, in: connection, since: period.start)
            if !records.isEmpty { break }
        }
        return Result(
            activity: ActivitySummary(records: records, since: period.today),
            history: ActivityHistory(records: records, period: period)
        )
    }

    private static func records(from source: Source, in connection: ReadOnlyDatabase, since: Date) throws -> [ActivityRecord] {
        // `time_created` is milliseconds since 1970, set from the message's own time.
        let sql = """
            SELECT id, time_created,
                   json_extract(data, '\(source.model)'),
                   json_extract(data, '$.tokens.input'),
                   json_extract(data, '$.tokens.output'),
                   json_extract(data, '$.tokens.reasoning'),
                   json_extract(data, '$.tokens.cache.read'),
                   json_extract(data, '$.tokens.cache.write')
            FROM \(source.table)
            WHERE time_created >= ? AND \(source.filter)
            """
        let since = Int64((since.timeIntervalSince1970 * 1000).rounded(.down))
        return try connection.rows(sql, values: [.integer(since)]) { row -> ActivityRecord? in
            guard let id = row.text(0), let created = row.integer(1) else { return nil }
            // OpenCode's `input` excludes cached tokens, and reasoning is
            // counted apart from visible output; both are billed as output.
            let breakdown = TokenBreakdown(
                input: max(0, row.integer(3) ?? 0),
                output: max(0, row.integer(4) ?? 0) + max(0, row.integer(5) ?? 0),
                cacheWrite: max(0, row.integer(7) ?? 0),
                cacheRead: max(0, row.integer(6) ?? 0)
            )
            // A message that failed before the model answered has no tokens.
            guard breakdown.total > 0 else { return nil }
            return ActivityRecord(
                key: id,
                timestamp: Date(timeIntervalSince1970: TimeInterval(created) / 1000),
                tokens: breakdown.total,
                model: row.text(2),
                breakdown: breakdown
            )
        }.compactMap { $0 }
    }
}
