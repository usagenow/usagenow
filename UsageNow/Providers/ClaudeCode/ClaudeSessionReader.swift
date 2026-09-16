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
        /// The latest limit Claude Code reported hitting, per window.
        var limitHits: [ClaudeLimitHit] = []
    }

    private let cache = IncrementalFileCache<ClaudeSessionFileState>()

    func todaysActivity(roots: [URL], since: Date) async -> Result {
        let files = SessionFileFinder.jsonlFiles(in: roots, modifiedSince: since)
        await cache.retain(only: Set(files.map(\.url)))

        var records: [ActivityRecord] = []
        var hits: [String: ClaudeLimitHit] = [:]
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
                for hit in state.limitHits.values where hit.observedAt >= (hits[hit.window.id]?.observedAt ?? .distantPast) {
                    hits[hit.window.id] = hit
                }
            } catch {
                Log.provider.debug("Skipped an unreadable Claude Code session file")
            }
        }
        return Result(
            activity: ActivitySummary(records: records, since: since),
            hasSessionFiles: !files.isEmpty,
            limitHits: hits.values.sorted { $0.window.id < $1.window.id }
        )
    }
}

struct ClaudeSessionFileState: Sendable {
    var records: [ActivityRecord] = []
    var limitHits: [String: ClaudeLimitHit] = [:]
}

/// A limit Claude Code reported reaching, from the notice it records when it
/// stops a request. It says the window is used up until it resets — nothing
/// about usage before that — so it's credential-free but only appears at 100%.
struct ClaudeLimitHit: Sendable, Equatable {
    var window: UsageWindow
    /// When Claude Code recorded it.
    var observedAt: Date
}

enum ClaudeSessionParser {
    private static let assistantMarker = Data(#""assistant""#.utf8)
    private static let usageMarker = Data(#""usage""#.utf8)
    /// Placeholder model Claude Code uses for locally generated messages.
    private static let syntheticModel = "<synthetic>"
    private static let decoder = JSONDecoder()

    private static let quotaLimitsMarker = Data(#""quotaLimits""#.utf8)

    static func fold(_ line: Data, into state: inout ClaudeSessionFileState, fileKey: String, since: Date) {
        if line.contains(quotaLimitsMarker) {
            foldLimitHit(line, into: &state)
        }
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
            breakdown: usage.breakdown
        ))
    }
}

extension ClaudeSessionParser {
    /// `quotaLimits` with `status: "rejected"` means the named window is used
    /// up until `resetsAt`. Other statuses carry no usable number.
    static func foldLimitHit(_ line: Data, into state: inout ClaudeSessionFileState) {
        guard let record = try? JSONDecoder().decode(ClaudeQuotaLimitsLine.self, from: line),
              let limits = record.quotaLimits,
              limits.status == "rejected",
              let type = limits.rateLimitType,
              let (kind, scope) = ClaudeUsageLimitsParser.window(forKey: type),
              let seconds = limits.resetsAt, seconds > 0,
              let observedAt = SessionTimestamp.parse(record.timestamp) else { return }
        let resetsAt = Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
        let window = UsageWindow(kind: kind, scope: scope, usage: UsagePercentage(percent: 100), resetsAt: resetsAt)
        if observedAt >= (state.limitHits[window.id]?.observedAt ?? .distantPast) {
            state.limitHits[window.id] = ClaudeLimitHit(window: window, observedAt: observedAt)
        }
    }
}

private struct ClaudeQuotaLimitsLine: Decodable {
    struct QuotaLimits: Decodable {
        var status: String?
        var rateLimitType: String?
        var resetsAt: Double?
    }

    var timestamp: String?
    var quotaLimits: QuotaLimits?
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

        /// The split Claude records, kept apart because each part is priced
        /// differently: a cache read costs a tenth of fresh input, a cache
        /// write a quarter more.
        var breakdown: TokenBreakdown? {
            guard inputSideTokens != nil || output_tokens != nil else { return nil }
            return TokenBreakdown(
                input: max(0, input_tokens ?? 0),
                output: max(0, output_tokens ?? 0),
                cacheWrite: max(0, cache_creation_input_tokens ?? 0),
                cacheRead: max(0, cache_read_input_tokens ?? 0)
            )
        }
    }

    var type: String?
    var timestamp: String?
    var requestId: String?
    var message: Message?
}
