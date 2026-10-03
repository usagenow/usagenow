import Foundation

/// Reads local activity from Qwen Code's session recordings
/// (`~/.qwen/projects/<project>/chats/<session>.jsonl`).
///
/// Qwen Code appends a record per message and attaches the model's token
/// counts (`usageMetadata`) to each answer. Only each answer's identifier,
/// time, model, and counts are decoded; the message itself is never decoded.
struct QwenCodeSessionReader: Sendable {
    struct Result: Sendable, Equatable {
        /// Today's activity.
        var activity: ActivitySummary
        var history: ActivityHistory
        var hasSessionFiles: Bool
    }

    private let cache = IncrementalFileCache<[ActivityRecord]>()

    func activity(root: URL, period: ActivityPeriod) async -> Result {
        let since = period.start
        // Chats only: the same tree holds workflow journals that aren't answers.
        let files = SessionFileFinder.jsonlFiles(in: [root], modifiedSince: since)
            .filter { $0.url.deletingLastPathComponent().lastPathComponent == "chats" }
        await cache.retain(only: Set(files.map(\.url)))

        var records: [ActivityRecord] = []
        for file in files {
            do {
                records += try await cache.state(
                    for: file,
                    initial: { [] },
                    prune: { $0.removeAll { $0.timestamp < since } },
                    fold: { line, records in QwenCodeSessionParser.fold(line, into: &records, since: since) }
                )
            } catch {
                Log.provider.debug("Skipped an unreadable Qwen Code session file")
            }
        }
        return Result(
            activity: ActivitySummary(records: records, since: period.today),
            history: ActivityHistory(records: records, period: period),
            hasSessionFiles: !files.isEmpty
        )
    }
}

enum QwenCodeSessionParser {
    private static let usageMarker = Data(#""usageMetadata""#.utf8)
    private static let decoder = JSONDecoder()

    static func fold(_ line: Data, into records: inout [ActivityRecord], since: Date) {
        guard line.contains(usageMarker),
              let record = try? decoder.decode(Line.self, from: line),
              record.type == "assistant",
              let usage = record.usageMetadata,
              let timestamp = SessionTimestamp.parse(record.timestamp),
              timestamp >= since,
              usage.totalTokens > 0 else { return }
        // A resumed session copies earlier records, with their identifiers.
        let key = record.uuid ?? "\(record.sessionId ?? "")#\(timestamp.timeIntervalSince1970)"
        records.append(ActivityRecord(
            key: key,
            timestamp: timestamp,
            tokens: usage.totalTokens,
            model: record.model,
            breakdown: usage.breakdown
        ))
    }

    /// The subset of a recording line UsageNow reads. `message` isn't
    /// declared, so its content is never decoded.
    private struct Line: Decodable {
        var uuid: String?
        var sessionId: String?
        var timestamp: String?
        var type: String?
        var model: String?
        var usageMetadata: Usage?
    }

    /// Gemini's usage shape, which Qwen Code keeps from Gemini CLI.
    struct Usage: Decodable {
        /// The whole prompt, cached part included.
        var promptTokenCount: Int64?
        var candidatesTokenCount: Int64?
        var cachedContentTokenCount: Int64?
        var thoughtsTokenCount: Int64?
        var totalTokenCount: Int64?

        var totalTokens: Int64 {
            if let totalTokenCount, totalTokenCount > 0 { return totalTokenCount }
            return max(0, promptTokenCount ?? 0) + outputTokens
        }

        /// Thinking is billed as output.
        var outputTokens: Int64 { max(0, candidatesTokenCount ?? 0) + max(0, thoughtsTokenCount ?? 0) }

        var breakdown: TokenBreakdown {
            let cached = max(0, cachedContentTokenCount ?? 0)
            return TokenBreakdown(
                input: max(0, (promptTokenCount ?? 0) - cached),
                output: outputTokens,
                cacheRead: cached
            )
        }
    }
}
