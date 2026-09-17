import Foundation
import SQLite3

/// Today's Warp agent activity, read from Warp's local database.
///
/// - Requests: rows in `ai_queries`, which has one per prompt with its time
///   and outcome. Its text column is never selected.
/// - Credits and models: `agent_conversations.conversation_data` carries a
///   running `conversation_usage_metadata` per conversation — credits spent
///   and tokens per model. Only that object is decoded; the messages beside
///   it in the same JSON are skipped by the decoder.
///
/// Those totals cover a whole conversation, not a day. A conversation whose
/// first prompt was today is counted in full; one that began earlier and
/// continued today can't be split honestly, so it's left out and today's
/// credits are marked partial instead of being overstated.
struct WarpActivityReader: Sendable {
    struct Result: Sendable, Equatable {
        var requests: Int64
        var credits: Decimal?
        var isCreditsComplete: Bool
        var models: [ModelActivity]
        /// The model most recently reported in a conversation active today.
        var latestModel: String?
    }

    /// How Warp writes `start_ts` and `last_modified_at`: UTC, without a zone.
    var databaseTimeZone: TimeZone = .gmt

    func todaysActivity(database: URL, since: Date) throws -> Result {
        let connection = try WarpDatabase(url: database)
        let sinceText = WarpDatabase.timestamp(since, in: databaseTimeZone)

        // Failed prompts never reached a model; pending ones haven't yet.
        let queries = try connection.rows(
            "SELECT conversation_id, output_status FROM ai_queries WHERE start_ts >= ?",
            bind: [sinceText]
        ) { row in (conversation: row.text(0), status: row.text(1)) }
        let answered = queries.filter { !["\"Failed\"", "\"Pending\"", "Failed", "Pending"].contains($0.status ?? "") }

        let active = Set(queries.compactMap(\.conversation))
        var startedToday: Set<String> = []
        if !active.isEmpty {
            let placeholders = Array(repeating: "?", count: active.count).joined(separator: ",")
            let firsts = try connection.rows(
                "SELECT conversation_id, MIN(start_ts) FROM ai_queries WHERE conversation_id IN (\(placeholders)) GROUP BY conversation_id",
                bind: Array(active)
            ) { row in (conversation: row.text(0), first: row.text(1)) }
            startedToday = Set(firsts.compactMap { $0.first.map { first in first >= sinceText } == true ? $0.conversation : nil })
        }

        var credits: Decimal?
        var isComplete = true
        var tokensByModel: [String: Int64] = [:]
        var latestModel: String?

        let conversations = try connection.rows(
            "SELECT conversation_id, conversation_data FROM agent_conversations WHERE last_modified_at >= ? ORDER BY last_modified_at",
            bind: [sinceText]
        ) { row in (id: row.text(0), data: row.data(1)) }

        for conversation in conversations {
            guard let id = conversation.id, let data = conversation.data,
                  let usage = try? JSONDecoder().decode(ConversationData.self, from: data).conversation_usage_metadata
            else { continue }

            if let model = usage.token_usage?.last(where: { $0.tokens > 0 })?.model_id {
                latestModel = model
            }
            guard startedToday.contains(id) else {
                // Active today, but its totals include earlier days.
                if (usage.credits_spent ?? 0) > 0 { isComplete = false }
                continue
            }
            if let spent = usage.credits_spent, spent.isFinite, spent >= 0 {
                credits = (credits ?? 0) + Decimal(spent)
            }
            for entry in usage.token_usage ?? [] {
                guard let model = entry.model_id, !model.isEmpty, entry.tokens > 0 else { continue }
                tokensByModel[model, default: 0] += entry.tokens
            }
        }

        let models = tokensByModel.map {
            ModelActivity(modelID: $0.key, totalTokens: $0.value, requests: 0, isRequestCountKnown: false)
        }.sortedByActivity()
        return Result(
            requests: Int64(answered.count),
            credits: credits ?? (isComplete ? 0 : nil),
            isCreditsComplete: isComplete,
            models: models,
            latestModel: latestModel
        )
    }

    private struct ConversationData: Decodable {
        struct Usage: Decodable {
            struct TokenUsage: Decodable {
                var model_id: String?
                /// How Warp recorded tokens before splitting them by who pays.
                var total_tokens: Int64?
                /// Current Warp: tokens on Warp's credits, on the person's own
                /// provider key, and on a custom endpoint.
                var warp_tokens: Int64?
                var byok_tokens: Int64?
                var custom_endpoint_tokens: Int64?

                var tokens: Int64 {
                    if let total_tokens { return max(0, total_tokens) }
                    return [warp_tokens, byok_tokens, custom_endpoint_tokens].compactMap { $0 }.map { max(0, $0) }.reduce(0, +)
                }
            }

            var credits_spent: Double?
            var token_usage: [TokenUsage]?
        }

        var conversation_usage_metadata: Usage?
    }
}

/// A read-only connection to Warp's database. Never writes, never migrates.
private final class WarpDatabase {
    enum Failure: Error {
        case open(Int32)
        case query(Int32)
    }

    struct Row {
        let statement: OpaquePointer

        func text(_ column: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: bytes)
        }

        func data(_ column: Int32) -> Data? {
            guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK else {
            sqlite3_close(handle)
            throw Failure.open(status)
        }
        // Warp may be writing; wait briefly instead of failing the refresh.
        sqlite3_busy_timeout(handle, 500)
    }

    deinit {
        sqlite3_close(handle)
    }

    func rows<T>(_ sql: String, bind values: [String], map: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw Failure.query(prepared) }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }

        var results: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                results.append(map(Row(statement: statement)))
            } else if step == SQLITE_DONE {
                return results
            } else {
                throw Failure.query(step)
            }
        }
    }

    /// Warp's format: "2026-09-13 15:42:01.495945". Comparing these as text
    /// orders them correctly, so no parsing is needed for the filters.
    static func timestamp(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }
}
