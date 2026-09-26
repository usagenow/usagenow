import Foundation

/// Reads the credits Qoder's agent spent from its transcripts
/// (`~/.qoder/projects/<project>/<session>.jsonl`).
///
/// Each answer from the model carries `message.usage.credits` — what Qoder
/// charged for it, after any discount. Qoder zeroes the token counts beside
/// it and names the model by an internal alias, so credits and a count of
/// answers are all there is to show. Only the time, identifiers, and the
/// credit fields are decoded; prompts, replies, and tool results on the
/// same lines are never decoded.
struct QoderSessionReader: Sendable {
    struct Result: Sendable, Equatable {
        /// Today's credits and model answers.
        var credits: Decimal
        var requests: Int64
        var history: ActivityHistory
        var hasSessionFiles: Bool
    }

    private let cache = IncrementalFileCache<QoderSessionFileState>()

    func activity(root: URL, period: ActivityPeriod) async -> Result {
        let since = period.start
        let files = SessionFileFinder.jsonlFiles(in: [root], modifiedSince: since)
        await cache.retain(only: Set(files.map(\.url)))

        var answers: [String: QoderAnswer] = [:]
        for file in files {
            let key = file.url.lastPathComponent
            do {
                let state = try await cache.state(
                    for: file,
                    initial: { QoderSessionFileState() },
                    prune: { state in state.answers = state.answers.filter { $0.value.timestamp >= since } },
                    fold: { line, state in QoderSessionParser.fold(line, into: &state, fileKey: key, since: since) }
                )
                // Keyed by request, so a copied or resumed session counts once.
                answers.merge(state.answers) { current, _ in current }
            } catch {
                Log.provider.debug("Skipped an unreadable Qoder session file")
            }
        }

        let today = answers.values.filter { $0.timestamp >= period.today }
        return Result(
            credits: today.reduce(Decimal.zero) { $0 + $1.credits },
            requests: Int64(today.count),
            history: ActivityHistory(credits: answers.values.map { ($0.timestamp, $0.credits) }, period: period),
            hasSessionFiles: !files.isEmpty
        )
    }
}

struct QoderAnswer: Sendable, Equatable {
    var timestamp: Date
    var credits: Decimal
}

struct QoderSessionFileState: Sendable {
    var answers: [String: QoderAnswer] = [:]
}

enum QoderSessionParser {
    private static let marker = Data(#""credits""#.utf8)
    private static let decoder = JSONDecoder()

    static func fold(_ line: Data, into state: inout QoderSessionFileState, fileKey: String, since: Date) {
        guard line.contains(marker),
              let record = try? decoder.decode(Line.self, from: line),
              record.type == "assistant",
              let usage = record.message?.usage,
              let credits = usage.credits, credits.isFinite, credits >= 0,
              let timestamp = SessionTimestamp.parse(record.timestamp),
              timestamp >= since
        else { return }

        let key = usage.request_id ?? record.message?.id ?? "\(fileKey)#\(timestamp.timeIntervalSince1970)"
        // An answer Qoder marks as not billable cost nothing, whatever it records.
        let charged = usage.billable == false ? Decimal.zero : APIAmount.decimal(credits) ?? 0
        state.answers[key] = QoderAnswer(timestamp: timestamp, credits: charged)
    }

    /// The subset of a transcript line UsageNow reads. Message content isn't
    /// declared, so it's never decoded.
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var credits: Double?
                var billable: Bool?
                var request_id: String?
            }

            var id: String?
            var usage: Usage?
        }

        var type: String?
        var timestamp: String?
        var message: Message?
    }
}
