import Foundation

/// Reads today's credits and prompt turns from Kiro's session records
/// (`~/.kiro/sessions/<workspace>/sess_<id>/messages.jsonl`).
///
/// After each prompt turn Kiro appends a `usage_summary` record saying how
/// many credits it used. Only those records are decoded, and only their
/// identifier, time, and credit amounts. Messages, tool calls, and file
/// contents on the other lines are never decoded.
///
/// Kiro records no token counts or model per turn, so there is no per-model
/// list and no cost estimate for it.
struct KiroSessionReader: Sendable {
    struct Result: Sendable, Equatable {
        var credits: Decimal
        var turns: Int64
        var hasSessionFiles: Bool
    }

    private let cache = IncrementalFileCache<KiroSessionFileState>()

    func todaysActivity(root: URL, since: Date) async -> Result {
        let files = SessionFileFinder.jsonlFiles(in: [root], modifiedSince: since)
            .filter { $0.url.lastPathComponent == "messages.jsonl" }
        await cache.retain(only: Set(files.map(\.url)))

        var turns: [String: KiroTurn] = [:]
        for file in files {
            do {
                let state = try await cache.state(
                    for: file,
                    initial: { KiroSessionFileState() },
                    prune: { state in state.turns = state.turns.filter { $0.value.timestamp >= since } },
                    fold: { line, state in KiroSessionParser.fold(line, into: &state, since: since) }
                )
                // Keyed by record identifier, so a copied session counts once.
                turns.merge(state.turns) { current, _ in current }
            } catch {
                Log.provider.debug("Skipped an unreadable Kiro session file")
            }
        }

        return Result(
            credits: turns.values.reduce(Decimal.zero) { $0 + $1.credits },
            turns: Int64(turns.count),
            hasSessionFiles: !files.isEmpty
        )
    }
}

struct KiroTurn: Sendable, Equatable {
    var timestamp: Date
    var credits: Decimal
}

struct KiroSessionFileState: Sendable {
    var turns: [String: KiroTurn] = [:]
}

enum KiroSessionParser {
    private static let marker = Data(#""usage_summary""#.utf8)
    private static let decoder = JSONDecoder()

    static func fold(_ line: Data, into state: inout KiroSessionFileState, since: Date) {
        guard line.contains(marker),
              let record = try? decoder.decode(Line.self, from: line),
              record.payload?.type == "usage_summary",
              let id = record.id ?? record.payload?.executionId, !id.isEmpty,
              let timestamp = SessionTimestamp.parse(record.timestamp),
              timestamp >= since
        else { return }

        // Only amounts in credits count; another unit would be a different meter.
        let credits = (record.payload?.promptTurnSummaries ?? [])
            .filter { $0.unit?.lowercased() == "credit" }
            .compactMap(\.usage)
            .filter { $0.isFinite && $0 >= 0 }
            .reduce(Decimal.zero) { $0 + Decimal($1) }

        state.turns[id] = KiroTurn(timestamp: timestamp, credits: credits)
    }

    private struct Line: Decodable {
        struct Payload: Decodable {
            struct TurnSummary: Decodable {
                var unit: String?
                var usage: Double?
            }

            var type: String?
            var executionId: String?
            var promptTurnSummaries: [TurnSummary]?
        }

        var id: String?
        var timestamp: String?
        var payload: Payload?
    }
}
