import Foundation

/// Reads today's local activity from Gemini CLI session recordings
/// (`~/.gemini/tmp/<project>/chats/**/*.jsonl`).
///
/// Only message identifiers, timestamps, model identifiers, and token counts
/// are decoded. Prompts, responses, thoughts, and tool calls are never
/// decoded or kept.
///
/// Gemini CLI appends a record per change, and attaches token counts to a
/// response after first writing it, so the same message can appear more
/// than once. The last record for a message wins.
struct GeminiSessionReader: Sendable {
    struct Result: Sendable, Equatable {
        var activity: ActivitySummary
        var hasSessionFiles: Bool
    }

    private let cache = IncrementalFileCache<GeminiSessionFileState>()

    func todaysActivity(roots: [URL], since: Date) async -> Result {
        let files = SessionFileFinder.jsonlFiles(in: roots, modifiedSince: since)
            .filter { $0.url.pathComponents.contains("chats") }
        await cache.retain(only: Set(files.map(\.url)))

        var records: [ActivityRecord] = []
        for file in files {
            do {
                let state = try await cache.state(
                    for: file,
                    initial: { GeminiSessionFileState() },
                    prune: { state in state.responses = state.responses.filter { $0.value.timestamp >= since } },
                    fold: { line, state in GeminiSessionParser.fold(line, into: &state, since: since) }
                )
                records += state.responses.values
            } catch {
                Log.provider.debug("Skipped an unreadable Gemini CLI session file")
            }
        }
        return Result(activity: ActivitySummary(records: records, since: since), hasSessionFiles: !files.isEmpty)
    }
}

struct GeminiSessionFileState: Sendable {
    /// One record per model response, keyed by message identifier.
    var responses: [String: ActivityRecord] = [:]
}

enum GeminiSessionParser {
    private static let responseMarker = Data(#""gemini""#.utf8)
    private static let tokensMarker = Data(#""tokens""#.utf8)
    private static let decoder = JSONDecoder()

    static func fold(_ line: Data, into state: inout GeminiSessionFileState, since: Date) {
        guard line.contains(tokensMarker), line.contains(responseMarker),
              let record = try? decoder.decode(GeminiSessionLine.self, from: line),
              record.type == "gemini",
              let id = record.id, !id.isEmpty,
              let tokens = record.tokens,
              let timestamp = SessionTimestamp.parse(record.timestamp),
              timestamp >= since else { return }

        state.responses[id] = ActivityRecord(
            key: id,
            timestamp: timestamp,
            tokens: tokens.totalTokens,
            model: record.model,
            breakdown: tokens.breakdown
        )
    }
}

/// The subset of a Gemini CLI session record UsageNow reads. `content`,
/// `thoughts`, and `toolCalls` aren't declared, so they're never decoded.
private struct GeminiSessionLine: Decodable {
    struct Tokens: Decodable {
        var input: Int64?
        var output: Int64?
        var cached: Int64?
        var thoughts: Int64?
        var tool: Int64?
        var total: Int64?

        var totalTokens: Int64 {
            total ?? [input, output, thoughts, tool].compactMap { $0 }.reduce(0, +)
        }

        /// Visible output plus reasoning, which is generated output too.
        var outputTokens: Int64? {
            let parts = [output, thoughts].compactMap { $0 }
            return parts.isEmpty ? nil : parts.reduce(0, +)
        }

        /// `cached` is a share of `input` rather than an addition to it, and
        /// is billed far below fresh input, so it's kept apart. Tool tokens
        /// are input the model was given.
        var breakdown: TokenBreakdown? {
            guard input != nil || output != nil else { return nil }
            let cached = max(0, cached ?? 0)
            let fresh = max(0, input ?? 0)
            return TokenBreakdown(
                input: max(0, fresh - cached) + max(0, tool ?? 0),
                output: max(0, outputTokens ?? 0),
                cacheRead: Swift.min(cached, fresh)
            )
        }
    }

    var id: String?
    var timestamp: String?
    var type: String?
    var model: String?
    var tokens: Tokens?
}
