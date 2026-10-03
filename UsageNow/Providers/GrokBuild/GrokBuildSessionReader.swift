import Foundation

/// Reads local activity from Grok Build's session logs
/// (`~/.grok/sessions/<project>/<session>/updates.jsonl`).
///
/// When a turn ends, Grok Build records a `turn_completed` update with the
/// turn's usage per model: tokens, cache reads and writes, model calls, and
/// the cost xAI reported. Only those numbers, the model names, and the time
/// are decoded. The turn's result text on the same line, and every other
/// update — prompts, replies, tool calls — are never decoded.
struct GrokBuildSessionReader: Sendable {
    struct Result: Sendable, Equatable {
        /// Today's activity.
        var activity: ActivitySummary
        var history: ActivityHistory
        var hasSessionFiles: Bool
    }

    private let cache = IncrementalFileCache<[ActivityRecord]>()

    func activity(root: URL, period: ActivityPeriod) async -> Result {
        let since = period.start
        let files = SessionFileFinder.jsonlFiles(in: [root], modifiedSince: since)
            .filter { $0.url.lastPathComponent == "updates.jsonl" }
        await cache.retain(only: Set(files.map(\.url)))

        var records: [ActivityRecord] = []
        for file in files {
            do {
                records += try await cache.state(
                    for: file,
                    initial: { [] },
                    prune: { $0.removeAll { $0.timestamp < since } },
                    fold: { line, records in GrokBuildSessionParser.fold(line, into: &records, since: since) }
                )
            } catch {
                Log.provider.debug("Skipped an unreadable Grok Build session file")
            }
        }
        return Result(
            activity: ActivitySummary(records: records, since: period.today),
            history: ActivityHistory(records: records, period: period),
            hasSessionFiles: !files.isEmpty
        )
    }
}

enum GrokBuildSessionParser {
    private static let marker = Data(#""turn_completed""#.utf8)
    /// xAI reports cost in ticks: 10¹⁰ ticks to the dollar.
    private static let ticksPerDollar = Decimal(10_000_000_000)
    private static let decoder = JSONDecoder()

    static func fold(_ line: Data, into records: inout [ActivityRecord], since: Date) {
        guard line.contains(marker),
              let envelope = try? decoder.decode(Envelope.self, from: line),
              let update = envelope.params?.update,
              update.sessionUpdate == "turn_completed",
              let usage = update.usage,
              let seconds = envelope.timestamp, seconds > 0 else { return }
        let timestamp = Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
        guard timestamp >= since else { return }

        let turn = "\(envelope.params?.sessionId ?? "")|\(update.prompt_id ?? String(seconds))"
        // xAI's cost can't be trusted for a turn whose usage is incomplete.
        let costIsTrusted = usage.usageIsIncomplete != true
        let rows: [(String?, Usage)] = (usage.modelUsage ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        for (model, row) in rows.isEmpty ? [(nil, usage.totals)] : rows {
            guard row.tokens > 0 else { continue }
            records.append(ActivityRecord(
                key: "\(turn)|\(model ?? "")",
                timestamp: timestamp,
                tokens: row.tokens,
                model: model,
                breakdown: row.breakdown,
                requests: max(1, row.modelCalls ?? 1),
                cost: costIsTrusted ? row.costUsdTicks.flatMap { row.costIsPartial == true ? nil : Decimal($0) / ticksPerDollar } : nil
            ))
        }
    }

    /// One line of `updates.jsonl`: when it was written, and the update.
    private struct Envelope: Decodable {
        struct Params: Decodable {
            var sessionId: String?
            var update: Update?
        }

        /// Seconds since 1970.
        var timestamp: Double?
        var params: Params?
    }

    /// The subset of a `turn_completed` update UsageNow reads. The turn's
    /// result text isn't declared, so it's never decoded.
    private struct Update: Decodable {
        var sessionUpdate: String?
        var prompt_id: String?
        var usage: TurnUsage?
    }

    private struct TurnUsage: Decodable {
        var totals: Usage
        var modelUsage: [String: Usage]?
        var usageIsIncomplete: Bool?

        init(from decoder: any Decoder) throws {
            // The totals sit beside `modelUsage`, flattened into the same object.
            totals = try Usage(from: decoder)
            let container = try decoder.container(keyedBy: Keys.self)
            modelUsage = try container.decodeIfPresent([String: Usage].self, forKey: .modelUsage)
            usageIsIncomplete = try container.decodeIfPresent(Bool.self, forKey: .usageIsIncomplete)
        }

        private enum Keys: String, CodingKey {
            case modelUsage, usageIsIncomplete
        }
    }

    struct Usage: Decodable {
        /// The whole prompt, cache reads and writes included.
        var inputTokens: Int64?
        var outputTokens: Int64?
        var cachedReadTokens: Int64?
        var cacheCreationTokens: Int64?
        var modelCalls: Int64?
        var costUsdTicks: Int64?
        var costIsPartial: Bool?

        var tokens: Int64 { max(0, inputTokens ?? 0) + max(0, outputTokens ?? 0) }

        var breakdown: TokenBreakdown {
            let read = max(0, cachedReadTokens ?? 0)
            let write = max(0, cacheCreationTokens ?? 0)
            return TokenBreakdown(
                input: max(0, (inputTokens ?? 0) - read - write),
                output: max(0, outputTokens ?? 0),
                cacheWrite: write,
                cacheRead: read
            )
        }
    }
}
