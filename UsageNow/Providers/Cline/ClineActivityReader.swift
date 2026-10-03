import Foundation

/// Reads local activity from Cline's saved tasks and sessions.
///
/// Cline records every API request it makes with its token counts and the
/// cost it worked out for it. UsageNow reads only those numbers, the model,
/// and the time:
///
/// - In an editor task (`ui_messages.json`), each request is a message whose
///   text is a small JSON object with `tokensIn`, `tokensOut`, `cacheReads`,
///   `cacheWrites`, and `cost`. Cline stores the request it sent in the same
///   object; it passes through memory while the numbers are read, and is
///   never kept or logged. Every other message is skipped.
/// - In a CLI session (`*.messages.json`), each answer carries `metrics`
///   beside its content; the content isn't declared, so it's never decoded.
///
/// These files are rewritten whole as a task goes on, so each is parsed
/// again only when it changes.
struct ClineActivityReader: Sendable {
    struct Result: Sendable, Equatable {
        /// Today's activity.
        var activity: ActivitySummary
        var history: ActivityHistory
        var hasTasks: Bool
    }

    private let tasks = WholeFileCache<[ActivityRecord]>()
    private let sessions = WholeFileCache<[ActivityRecord]>()

    func activity(environment: ClineEnvironment, period: ActivityPeriod) async -> Result {
        let since = period.start
        let taskFiles = SessionFileFinder.files(
            named: "ui_messages.json",
            oneLevelBelow: environment.extensionTaskRoots + [environment.cliTasksRoot].compactMap { $0 },
            modifiedSince: since
        )
        let sessionFiles = cliSessionFiles(environment: environment, since: since)
        await tasks.retain(only: Set(taskFiles.map(\.url)))
        await sessions.retain(only: Set(sessionFiles.map(\.url)))

        var records: [ActivityRecord] = []
        for file in taskFiles {
            let task = file.url.deletingLastPathComponent().lastPathComponent
            do {
                records += try await tasks.value(for: file) { data in
                    ClineTaskParser.records(from: data, task: task)
                }
            } catch {
                Log.provider.debug("Skipped an unreadable Cline task")
            }
        }
        for file in sessionFiles {
            do {
                records += try await sessions.value(for: file) { data in
                    ClineSessionParser.records(from: data)
                }
            } catch {
                Log.provider.debug("Skipped an unreadable Cline session")
            }
        }
        records.removeAll { $0.timestamp < since }

        return Result(
            activity: ActivitySummary(records: records, since: period.today),
            history: ActivityHistory(records: records, period: period),
            hasTasks: !taskFiles.isEmpty || !sessionFiles.isEmpty
        )
    }

    /// `sessions/<id>/<id>.messages.json`: each session folder holds a file
    /// named after itself.
    private func cliSessionFiles(environment: ClineEnvironment, since: Date) -> [SessionFile] {
        guard let root = environment.cliSessionsRoot else { return [] }
        return SessionFileFinder.files(named: ".messages.json", oneLevelBelow: [root], modifiedSince: since, prefixedWithFolderName: true)
    }
}

/// An editor task's `ui_messages.json`: a JSON array of messages.
enum ClineTaskParser {
    private static let decoder = JSONDecoder()

    static func records(from data: Data, task: String) -> [ActivityRecord] {
        guard let messages = try? decoder.decode([Message].self, from: data) else { return [] }
        var records: [ActivityRecord] = []
        // Older tasks name the model only on some messages; the last named
        // one stands for the requests after it.
        var model: String?
        for message in messages {
            if let named = message.modelInfo?.modelId, !named.isEmpty { model = named }
            guard let request = message.request, let timestamp = message.timestamp else { continue }
            let tokens = request.tokens
            // A request still running has no counts yet.
            guard tokens > 0 || (request.cost ?? 0) > 0 else { continue }
            records.append(ActivityRecord(
                key: "\(task)|\(message.ts.map { String($0.seconds) } ?? "")",
                timestamp: timestamp,
                tokens: tokens,
                model: model,
                breakdown: request.breakdown,
                cost: APIAmount.decimal(request.cost)
            ))
        }
        return records
    }

    private struct Message: Decodable {
        var ts: FlexibleTimestamp?
        var modelInfo: ModelInfo?
        /// Set only for `say: api_req_started`, the one message read.
        var request: Request?

        var timestamp: Date? { ts.map { Date(timeIntervalSince1970: $0.seconds) } }

        private enum Keys: String, CodingKey {
            case ts, type, say, text, modelInfo
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            ts = try? container.decodeIfPresent(FlexibleTimestamp.self, forKey: .ts)
            modelInfo = try? container.decodeIfPresent(ModelInfo.self, forKey: .modelInfo)
            let say = try? container.decodeIfPresent(String.self, forKey: .say)
            // Only an API request's text is read; every other message's
            // text — replies, tool output — is left alone.
            if say == "api_req_started",
               let text = try? container.decodeIfPresent(String.self, forKey: .text) {
                request = try? JSONDecoder().decode(Request.self, from: Data(text.utf8))
            }
        }
    }

    private struct ModelInfo: Decodable {
        var modelId: String?
    }

    /// The counts in an API request message. The request Cline sent, stored
    /// beside them, isn't declared.
    private struct Request: Decodable {
        var tokensIn: Double?
        var tokensOut: Double?
        var cacheReads: Double?
        var cacheWrites: Double?
        var cost: Double?

        var breakdown: TokenBreakdown {
            TokenBreakdown(
                input: Self.count(tokensIn),
                output: Self.count(tokensOut),
                cacheWrite: Self.count(cacheWrites),
                cacheRead: Self.count(cacheReads)
            )
        }

        var tokens: Int64 { breakdown.total }

        private static func count(_ value: Double?) -> Int64 {
            guard let value, value.isFinite, value > 0 else { return 0 }
            return Int64(value)
        }
    }
}

/// A CLI session's `<id>.messages.json`.
enum ClineSessionParser {
    private static let decoder = JSONDecoder()

    static func records(from data: Data) -> [ActivityRecord] {
        guard let file = try? decoder.decode(File.self, from: data) else { return [] }
        let session = file.sessionId ?? ""
        return (file.messages ?? []).compactMap { message in
            guard message.role == "assistant",
                  let metrics = message.metrics,
                  let ts = message.ts else { return nil }
            let breakdown = TokenBreakdown(
                input: max(0, metrics.inputTokens ?? 0),
                output: max(0, metrics.outputTokens ?? 0),
                cacheWrite: max(0, metrics.cacheWriteTokens ?? 0),
                cacheRead: max(0, metrics.cacheReadTokens ?? 0)
            )
            guard breakdown.total > 0 else { return nil }
            return ActivityRecord(
                key: "\(session)|\(message.id ?? String(ts.seconds))",
                timestamp: Date(timeIntervalSince1970: ts.seconds),
                tokens: breakdown.total,
                model: message.modelInfo?.id,
                breakdown: breakdown,
                cost: APIAmount.decimal(metrics.cost)
            )
        }
    }

    private struct File: Decodable {
        var sessionId: String?
        var messages: [Message]?
    }

    /// An answer's identity and numbers. Its content isn't declared.
    private struct Message: Decodable {
        struct ModelInfo: Decodable {
            var id: String?
        }

        struct Metrics: Decodable {
            var inputTokens: Int64?
            var outputTokens: Int64?
            var cacheReadTokens: Int64?
            var cacheWriteTokens: Int64?
            var cost: Double?
        }

        var id: String?
        var role: String?
        var ts: FlexibleTimestamp?
        var modelInfo: ModelInfo?
        var metrics: Metrics?
    }
}

/// A time Cline writes as milliseconds since 1970, or as ISO 8601 text.
struct FlexibleTimestamp: Decodable, Sendable {
    var seconds: TimeInterval

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            seconds = number > 1e12 ? number / 1000 : number
        } else if let date = SessionTimestamp.parse(try container.decode(String.self)) {
            seconds = date.timeIntervalSince1970
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized timestamp")
        }
    }
}
