import Foundation

extension APIKeyProvider {
    static func miniMax(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .minimax, keys: keys, transport: transport) { client, key in
            try MiniMaxUsage.parse(await client.get("/v1/token_plan/remains", key: key))
        }
    }
}

/// Global M Plan quota, with an explicitly supplied subscription key. Contract:
/// https://platform.minimax.io/docs/m-plan/faq
/// Numeric field semantics: MiniMax-AI/cli src/types/api.ts + src/utils/quota.ts.
/// No browser, CLI sign-in, PAYG balance, or generating endpoint is accessed.
enum MiniMaxUsage {
    private struct Response: Decodable {
        struct Status: Decodable { var status_code: Int? }
        var base_resp: Status?
        var model_remains: [Model]?
    }
    private struct Model: Decodable {
        var model_name: String?
        var start_time: Double?
        var end_time: Double?
        var weekly_start_time: Double?
        var weekly_end_time: Double?
        var current_interval_total_count: Double?
        var current_interval_usage_count: Double?
        var current_interval_remaining_percent: Double?
        var current_weekly_total_count: Double?
        var current_weekly_usage_count: Double?
        var current_weekly_remaining_percent: Double?
        var current_interval_status: Int?
        var current_weekly_status: Int?
        var weekly_boost_permille: Double?
    }

    static func parse(_ data: Data) throws -> APIKeyReading {
        let body = try ConnectedUsage.decode(Response.self, from: data)
        if body.base_resp?.status_code == 1004 { throw APIKeyClient.Failure.rejectedKey }
        guard body.base_resp?.status_code == nil || body.base_resp?.status_code == 0,
              let models = body.model_remains, !models.isEmpty, models.count <= 128 else {
            throw APIKeyClient.Failure.unreadableResponse
        }
        var windows: [UsageWindow] = []
        for model in models {
            let scope = model.model_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let scope, !scope.isEmpty, scope.utf8.count <= 160 else { continue }
            if let window = window(start: model.start_time, end: model.end_time, total: model.current_interval_total_count,
                count: model.current_interval_usage_count, percent: model.current_interval_remaining_percent,
                status: model.current_interval_status, scope: scope) { windows.append(window) }
            if let window = window(start: model.weekly_start_time, end: model.weekly_end_time, total: model.current_weekly_total_count,
                count: model.current_weekly_usage_count, percent: model.current_weekly_remaining_percent,
                status: model.current_weekly_status, scope: scope, boost: model.weekly_boost_permille) { windows.append(window) }
        }
        // Conflicting duplicate buckets must not acquire an arbitrary value.
        let grouped = Dictionary(grouping: windows, by: \.id)
        windows = windows.filter { grouped[$0.id]?.count == 1 }
        guard !windows.isEmpty else { throw APIKeyClient.Failure.unreadableResponse }
        return APIKeyReading(windows: windows,
            quotaUnavailableReason: windows.contains(where: { $0.usage != nil }) ? nil : .temporarilyUnavailable)
    }

    private static func window(start: Double?, end: Double?, total: Double?, count: Double?, percent: Double?,
                               status: Int?, scope: String, boost: Double? = nil) -> UsageWindow? {
        // Status 3 means unlimited (or a bucket absent from this plan), not 0%.
        guard status != 3 else { return nil }
        guard (total ?? 0) > 0 || percent != nil || status == 2 else { return nil }
        let beginning = date(start)
        let reset = date(end)
        let kind: UsageWindowKind
        if let beginning, let reset, reset > beginning, reset.timeIntervalSince(beginning) <= 31 * 86400 {
            kind = UsageWindowKind(durationMinutes: max(1, Int((reset.timeIntervalSince(beginning) / 60).rounded())))
        } else { kind = .allowance }
        let usage: UsagePercentage?
        if let boost, (!boost.isFinite || boost != 1000) {
            // Extra allowance can exceed 100%. Until it has an unambiguous
            // denominator, keep the window/reset but no misleading percentage.
            usage = nil
        } else if status == 2 {
            usage = UsagePercentage(percent: 100)
        } else {
            usage = used(total: total, count: count, remainingPercent: percent)
        }
        return UsageWindow(kind: kind, scope: scope, usage: usage, resetsAt: reset)
    }

    private static func used(total: Double?, count: Double?, remainingPercent: Double?) -> UsagePercentage? {
        if let remainingPercent, (!remainingPercent.isFinite || !(0...100).contains(remainingPercent)) { return nil }
        if let total, let count {
            guard total.isFinite, count.isFinite, total > 0, (0...total).contains(count) else { return nil }
            let legacyRemaining = count / total * 100
            if let remainingPercent {
                // New responses can use usage_count as consumed; the explicit
                // remaining percentage disambiguates it. Contradictions stay unknown.
                guard min(abs(legacyRemaining - remainingPercent), abs(100 - legacyRemaining - remainingPercent)) <= 1 else { return nil }
                return UsagePercentage(percent: 100 - remainingPercent)
            }
            return UsagePercentage(percent: 100 - legacyRemaining)
        }
        return remainingPercent.flatMap { UsagePercentage(percent: 100 - $0) }
    }

    private static func date(_ milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds.isFinite,
              milliseconds >= 946684800000, milliseconds < 4102444800000 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
