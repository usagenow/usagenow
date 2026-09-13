import Foundation

/// Reads today's local activity from Claude Code session transcripts
/// (`~/.claude/projects/**/*.jsonl`).
///
/// Only timestamps, request and message identifiers, model identifiers,
/// and token counts are decoded. Prompts, assistant text, tool inputs, and
/// file contents are never decoded or kept.
///
/// Claude Code writes one line per content block of a response, repeating
/// the same usage on each, so responses are de-duplicated by
/// `(message.id, requestId)`. Token counts include cache reads and writes
/// as recorded locally; they're activity, not billing.
struct ClaudeSessionReader: Sendable {
    struct Result: Sendable, Equatable {
        var activity: ActivitySummary
        var hasSessionFiles: Bool
    }

    private let cache = IncrementalFileCache<ClaudeSessionFileState>()

    func todaysActivity(roots: [URL], since: Date) async -> Result {
        let files = SessionFileFinder.jsonlFiles(in: roots, modifiedSince: since)
        await cache.retain(only: Set(files.map(\.url)))

        var records: [ActivityRecord] = []
        for file in files {
            let key = file.url.lastPathComponent
            do {
                let state = try await cache.state(
                    for: file,
                    initial: { ClaudeSessionFileState() },
                    prune: { $0.records.removeAll { $0.timestamp < since } },
                    fold: { line, state in ClaudeSessionParser.fold(line, into: &state, fileKey: key, since: since) }
                )
                records += state.records
            } catch {
                Log.provider.debug("Skipped an unreadable Claude Code session file")
            }
        }
        return Result(activity: ActivitySummary(records: records, since: since), hasSessionFiles: !files.isEmpty)
    }
}

struct ClaudeSessionFileState: Sendable {
    var records: [ActivityRecord] = []
}

enum ClaudeSessionParser {
    private static let assistantMarker = Data(#""assistant""#.utf8)
    private static let usageMarker = Data(#""usage""#.utf8)
    /// Placeholder model Claude Code uses for locally generated messages.
    private static let syntheticModel = "<synthetic>"
    private static let decoder = JSONDecoder()

    static func fold(_ line: Data, into state: inout ClaudeSessionFileState, fileKey: String, since: Date) {
        guard line.contains(usageMarker), line.contains(assistantMarker),
              let record = try? decoder.decode(ClaudeSessionLine.self, from: line),
              record.type == "assistant",
              let usage = record.message?.usage,
              let timestamp = SessionTimestamp.parse(record.timestamp),
              timestamp >= since else { return }

        let model = record.message?.model
        guard model != syntheticModel else { return }

        let identity = [record.message?.id, record.requestId].compactMap { $0 }
        let key = identity.isEmpty ? "\(fileKey)#\(timestamp.timeIntervalSince1970)" : identity.joined(separator: "|")
        state.records.append(ActivityRecord(
            key: key,
            timestamp: timestamp,
            tokens: usage.totalTokens,
            model: model,
            inputTokens: usage.inputSideTokens,
            outputTokens: usage.output_tokens
        ))
    }
}

/// The subset of a Claude Code transcript line UsageNow reads.
private struct ClaudeSessionLine: Decodable {
    struct Message: Decodable {
        var id: String?
        var model: String?
        var usage: Usage?
    }

    struct Usage: Decodable {
        var input_tokens: Int64?
        var cache_creation_input_tokens: Int64?
        var cache_read_input_tokens: Int64?
        var output_tokens: Int64?

        var totalTokens: Int64 {
            (inputSideTokens ?? 0) + (output_tokens ?? 0)
        }

        /// Fresh input plus cache writes and reads; `nil` when none is recorded.
        var inputSideTokens: Int64? {
            let parts = [input_tokens, cache_creation_input_tokens, cache_read_input_tokens].compactMap { $0 }
            return parts.isEmpty ? nil : parts.reduce(0, +)
        }
    }

    var type: String?
    var timestamp: String?
    var requestId: String?
    var message: Message?
}
