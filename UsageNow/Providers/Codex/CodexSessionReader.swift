import Foundation

/// Reads today's local activity and the latest recorded rate limits from
/// Codex session files (`sessions/**/rollout-*.jsonl`).
///
/// Only token counts, model identifiers, and rate-limit fields are decoded.
/// Lines holding conversation content are skipped without being decoded,
/// and nothing read here is stored beyond in-memory aggregates.
struct CodexSessionReader: Sendable {
    struct Result: Sendable, Equatable {
        var activity: ActivitySummary
        var latestRateLimits: CodexRateLimitSnapshot?
        var hasSessionFiles: Bool
    }

    private let cache = IncrementalFileCache<CodexSessionFileState>()

    /// Activity since `since` (normally the start of today), from files modified since then.
    func todaysActivity(roots: [URL], since: Date) async -> Result {
        let files = SessionFileFinder.jsonlFiles(in: roots, modifiedSince: since)
        await cache.retain(only: Set(files.map(\.url)))

        var states: [CodexSessionFileState] = []
        for file in files {
            let key = file.url.lastPathComponent
            do {
                let state = try await cache.state(
                    for: file,
                    initial: { CodexSessionFileState() },
                    prune: { $0.discardRecords(before: since) },
                    fold: { line, state in CodexSessionParser.fold(line, into: &state, fileKey: key, since: since) }
                )
                states.append(state)
            } catch {
                Log.provider.debug("Skipped an unreadable Codex session file")
            }
        }

        var activity = ActivitySummary(records: states.flatMap(\.countedRecords), since: since)
        if let latest = states.compactMap(\.latestModel).max(by: { $0.date < $1.date }) {
            activity.latestModel = latest.model
            activity.latestModelAt = latest.date
        }
        return Result(
            activity: activity,
            latestRateLimits: states.compactMap(\.latestRateLimits).max { $0.capturedAt < $1.capturedAt },
            hasSessionFiles: !files.isEmpty
        )
    }

    /// The most recent rate limits recorded in any session, looking only at
    /// the tail of the newest files. Fallback for when the app-server is
    /// unavailable and nothing was recorded today.
    func latestRecordedRateLimits(roots: [URL], maxFiles: Int = 3, maxBytesPerFile: UInt64 = 2 * 1024 * 1024) -> CodexRateLimitSnapshot? {
        let newest = SessionFileFinder.jsonlFiles(in: roots, modifiedSince: .distantPast)
            .sorted { $0.modificationDate > $1.modificationDate }
            .prefix(maxFiles)
        for file in newest {
            guard let lines = try? JSONLReader.trailingLines(in: file.url, maxBytes: maxBytesPerFile) else { continue }
            for line in lines.reversed() {
                var state = CodexSessionFileState()
                CodexSessionParser.fold(line, into: &state, fileKey: "", since: .distantFuture)
                if let limits = state.latestRateLimits { return limits }
            }
        }
        return nil
    }
}

/// What's been learned from one session file so far.
struct CodexSessionFileState: Sendable {
    /// One per model response (`token_usage_record`, current Codex versions).
    var usageRecords: [ActivityRecord] = []
    /// From `token_count` events, for older versions without usage records.
    var legacyRecords: [ActivityRecord] = []
    var lastLegacyTotal: Int64?
    var latestModel: (model: String, date: Date)?
    var latestRateLimits: CodexRateLimitSnapshot?

    /// Prefers per-response records; falls back to legacy events only for
    /// files that have none, so a response is never counted twice.
    var countedRecords: [ActivityRecord] {
        usageRecords.isEmpty ? legacyRecords : usageRecords
    }

    mutating func discardRecords(before date: Date) {
        usageRecords.removeAll { $0.timestamp < date }
        legacyRecords.removeAll { $0.timestamp < date }
    }
}

enum CodexSessionParser {
    private static let tokenMarker = Data(#""token_"#.utf8)
    private static let turnContextMarker = Data(#""turn_context""#.utf8)
    private static let decoder = JSONDecoder()

    /// Folds one JSONL line into `state`. Malformed, unknown, or unrelated
    /// lines are ignored. Records before `since` aren't kept.
    static func fold(_ line: Data, into state: inout CodexSessionFileState, fileKey: String, since: Date) {
        // Cheap filter: only a few record types are relevant.
        guard line.contains(tokenMarker) || line.contains(turnContextMarker) else { return }
        guard let record = try? decoder.decode(CodexSessionLine.self, from: line),
              let timestamp = SessionTimestamp.parse(record.timestamp) else { return }
        let payload = record.payload

        switch record.type {
        case "token_usage_record":
            guard timestamp >= since, let usage = payload?.usage, let total = usage.totalTokens else { return }
            let key = payload?.response_id ?? "\(fileKey)#\(record.ordinal.map(String.init) ?? "\(timestamp.timeIntervalSince1970)")"
            // A response belongs to the model of the turn it's part of, which
            // the session records before the response.
            state.usageRecords.append(ActivityRecord(
                key: key,
                timestamp: timestamp,
                tokens: total,
                model: payload?.model ?? state.latestModel?.model,
                inputTokens: usage.input_tokens,
                outputTokens: usage.output_tokens
            ))

        case "turn_context":
            if let model = payload?.model, !model.isEmpty, timestamp >= (state.latestModel?.date ?? .distantPast) {
                state.latestModel = (model, timestamp)
            }

        case "event_msg" where payload?.type == "token_count":
            if let limits = payload?.rate_limits?.snapshot(capturedAt: timestamp),
               timestamp >= (state.latestRateLimits?.capturedAt ?? .distantPast) {
                state.latestRateLimits = limits
            }
            // Token counts repeat when only rate limits changed; count each new total once.
            guard let info = payload?.info,
                  let last = info.last_token_usage?.totalTokens,
                  let cumulative = info.total_token_usage?.totalTokens,
                  cumulative != state.lastLegacyTotal else { return }
            state.lastLegacyTotal = cumulative
            guard timestamp >= since else { return }
            let key = "\(fileKey)#legacy#\(cumulative)"
            state.legacyRecords.append(ActivityRecord(key: key, timestamp: timestamp, tokens: last, model: state.latestModel?.model))

        default:
            return
        }
    }
}

/// The subset of a Codex session line UsageNow reads. Every field is
/// optional so schema changes degrade gracefully.
private struct CodexSessionLine: Decodable {
    struct Payload: Decodable {
        var type: String?
        var response_id: String?
        var usage: TokenUsage?
        var model: String?
        var info: Info?
        var rate_limits: CodexRecordedRateLimits?
    }

    struct Info: Decodable {
        var total_token_usage: TokenUsage?
        var last_token_usage: TokenUsage?
    }

    struct TokenUsage: Decodable {
        var input_tokens: Int64?
        var output_tokens: Int64?
        var total_tokens: Int64?

        var totalTokens: Int64? {
            total_tokens ?? input_tokens.map { $0 + (output_tokens ?? 0) }
        }
    }

    var timestamp: String?
    var ordinal: Int?
    var type: String?
    var payload: Payload?
}
