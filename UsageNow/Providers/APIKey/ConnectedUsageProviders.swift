import Foundation

extension APIKeyProvider {
    static func cursor(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .cursor, keys: keys, transport: transport) { client, key in
            try CursorUsage.parse(try await client.get("/api/usage-summary", key: key))
        }
    }

    static func copilot(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .copilot, keys: keys, transport: transport) { client, key in
            try CopilotUsage.parse(try await client.get("/copilot_internal/user", key: key))
        }
    }

    static func perplexity(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .perplexity, keys: keys, transport: transport) { client, key in
            try PerplexityUsage.parse(try await client.get("/rest/billing/credits", key: key, query: [
                URLQueryItem(name: "version", value: "2.18"), URLQueryItem(name: "source", value: "default")
            ]))
        }
    }

    static func elevenLabs(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .elevenlabs, keys: keys, transport: transport) { client, key in
            try ElevenLabsUsage.parse(try await client.get("/v1/user/subscription", key: key))
        }
    }

    static func zai(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .zai, keys: keys, transport: transport) { client, key in
            try ZaiUsage.parse(try await client.get("/api/monitor/usage/quota/limit", key: key))
        }
    }
}

/// Parsing only: no authentication state or network access. Schema references
/// are pinned in docs/provider-connections.md (CodexBar, MIT; see notices).
enum ConnectedUsage {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let result = try? JSONDecoder().decode(type, from: data) else {
            throw APIKeyClient.Failure.unreadableResponse
        }
        return result
    }

    static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: value) { return date }
        // GitHub also returns a date without a clock. UTC is the billing
        // API's date boundary, not the Mac's current time zone.
        if value.count == 10 { return ISO8601DateFormatter().date(from: value + "T00:00:00Z") }
        return nil
    }

    static func unix(_ seconds: Double?) -> Date? {
        guard let seconds = nonnegative(seconds), seconds > 0, seconds < 253_402_300_800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func total(_ kind: UsageTotal.Kind, _ value: Double?) -> UsageTotal? {
        guard let number = nonnegative(value), let decimal = APIAmount.decimal(number) else { return nil }
        return UsageTotal(kind: kind, value: decimal)
    }

    /// Treat an empty/new response as unavailable, not as a zero balance.
    static func requireReading(_ reading: APIKeyReading) throws -> APIKeyReading {
        guard reading.balance != nil || !reading.windows.isEmpty || !reading.totals.isEmpty || reading.planName?.isEmpty == false else {
            throw APIKeyClient.Failure.unreadableResponse
        }
        return reading
    }
}

enum ElevenLabsUsage {
    private struct Response: Decodable {
        var character_count: Double
        var character_limit: Double
        var next_character_count_reset_unix: Double?
        var tier: String?
    }

    static func parse(_ data: Data) throws -> APIKeyReading {
        let value = try ConnectedUsage.decode(Response.self, from: data)
        guard let used = ConnectedUsage.nonnegative(value.character_count),
              let limit = ConnectedUsage.nonnegative(value.character_limit) else {
            throw APIKeyClient.Failure.unreadableResponse
        }
        return APIKeyReading(balance: nil, windows: limit > 0 ? [UsageWindow(
            kind: .monthly, usage: UsagePercentage(used: used, limit: limit),
            resetsAt: ConnectedUsage.unix(value.next_character_count_reset_unix)
        )] : [], planName: value.tier, totals: [ConnectedUsage.total(.charactersUsed, used)].compactMap { $0 })
    }
}

enum CursorUsage {
    private struct Response: Decodable {
        struct Usage: Decodable { var plan: Pool?; var overall: Pool? }
        struct Pool: Decodable {
            var enabled: Bool?
            var used: Double?
            var limit: Double?
            var remaining: Double?
            var totalPercentUsed: Double?
        }
        var billingCycleEnd: String?
        var membershipType: String?
        var isUnlimited: Bool?
        var individualUsage: Usage?
    }

    static func parse(_ data: Data) throws -> APIKeyReading {
        let value = try ConnectedUsage.decode(Response.self, from: data)
        var windows: [UsageWindow] = []
        func append(_ pool: Response.Pool?, scope: String? = nil) -> Bool {
            guard let pool, pool.enabled != false else { return false }
            let usage: UsagePercentage?
            if let limit = ConnectedUsage.nonnegative(pool.limit), limit > 0,
               let used = ConnectedUsage.nonnegative(pool.used) ?? ConnectedUsage.nonnegative(pool.remaining).map({ max(0, limit - $0) }) {
                usage = UsagePercentage(used: used, limit: limit)
            } else if let percent = ConnectedUsage.nonnegative(pool.totalPercentUsed), percent <= 100 {
                // Already a percent: 0.36 means 0.36%, not 36%.
                usage = UsagePercentage(percent: percent)
            } else { return false }
            windows.append(UsageWindow(kind: .monthly, scope: scope, usage: usage,
                                       resetsAt: ConnectedUsage.date(value.billingCycleEnd)))
            return true
        }
        if value.isUnlimited != true, !append(value.individualUsage?.plan) { _ = append(value.individualUsage?.overall) }
        // Team-wide counters are outside personal-account tracking. They
        // aren't decoded or substituted for the member's own allowance.
        return try ConnectedUsage.requireReading(APIKeyReading(balance: nil, windows: windows, planName: value.membershipType))
    }
}

enum CopilotUsage {
    /// Some versions of GitHub's endpoint encode counters as strings.
    private struct Number: Decodable {
        var value: Double
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) { value = number }
            else if let number = Double(try container.decode(String.self)), number.isFinite { value = number }
            else { throw APIKeyClient.Failure.unreadableResponse }
        }
    }
    private struct Quota: Decodable {
        var entitlement: Number?
        var remaining: Number?
        var percent_remaining: Number?
        var credits_used: Number?
        var unlimited: Bool?
    }
    private struct Response: Decodable {
        var copilot_plan: String?
        var quota_reset_date: String?
        var quota_snapshots: [String: Quota]?
        var token_based_billing: Bool?
        var monthly_quotas: [String: Number]?
        var limited_user_quotas: [String: Number]?
    }

    static func parse(_ data: Data) throws -> APIKeyReading {
        let value = try ConnectedUsage.decode(Response.self, from: data)
        var windows: [UsageWindow] = []
        let quotas = value.quota_snapshots ?? [:]
        for (key, scope) in [("premium_interactions", "Premium"), ("chat", "Chat"), ("completions", "Completions")] {
            guard let quota = quotas[key], quota.unlimited != true else { continue }
            let cap = ConnectedUsage.nonnegative(quota.entitlement?.value)
            let remaining = ConnectedUsage.nonnegative(quota.remaining?.value)
            // Token-based seats can return a zero/zero placeholder, even
            // with percent_remaining=100. It is NOT a full allowance.
            if cap == 0 && remaining == 0 { continue }
            let usage: UsagePercentage?
            if let cap, cap > 0, let remaining {
                usage = UsagePercentage(used: max(0, cap - remaining), limit: cap)
            } else if let remaining = ConnectedUsage.nonnegative(quota.percent_remaining?.value), remaining <= 100 {
                usage = UsagePercentage(percent: 100 - remaining)
            } else { continue }
            windows.append(UsageWindow(kind: .monthly, scope: scope, usage: usage,
                                       resetsAt: ConnectedUsage.date(value.quota_reset_date)))
        }
        // Older/free seats report the monthly cap and remaining count
        // separately. Use both only, never a hardcoded plan entitlement.
        if value.token_based_billing != true {
            for (key, scope) in [("chat", "Chat"), ("completions", "Completions")]
            where quotas[key]?.unlimited != true && !windows.contains(where: { $0.scope == scope }) {
                guard let cap = ConnectedUsage.nonnegative(value.monthly_quotas?[key]?.value), cap > 0,
                      let remaining = ConnectedUsage.nonnegative(value.limited_user_quotas?[key]?.value) else { continue }
                windows.append(UsageWindow(kind: .monthly, scope: scope, usage: UsagePercentage(used: max(0, cap - remaining), limit: cap),
                                           resetsAt: ConnectedUsage.date(value.quota_reset_date)))
            }
        }
        // These fields can describe the same pool. Never add them together.
        let used = quotas["premium_interactions"]?.credits_used?.value ?? quotas["chat"]?.credits_used?.value
        return try ConnectedUsage.requireReading(APIKeyReading(balance: nil, windows: windows, planName: value.copilot_plan,
            totals: [ConnectedUsage.total(.creditsUsed, used)].compactMap { $0 }))
    }
}

enum PerplexityUsage {
    private struct Response: Decodable {
        struct Grant: Decodable { var type: String; var amountCents: Double; var expiresAtTs: Double? }
        var balanceCents: Double
        var totalUsageCents: Double
        var renewalDateTs: Double?
        var creditGrants: [Grant]?
    }

    static func parse(_ data: Data, now: Date = .now) throws -> APIKeyReading {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let value = try? decoder.decode(Response.self, from: data),
              let remaining = ConnectedUsage.nonnegative(value.balanceCents),
              let used = ConnectedUsage.nonnegative(value.totalUsageCents) else { throw APIKeyClient.Failure.unreadableResponse }
        var windows: [UsageWindow] = []
        // Mixed purchased/bonus grants have different lifetimes. Show a
        // percentage only if the reported active pool reconciles exactly
        // with usage and balance; do not assume a consumption order.
        let grants = (value.creditGrants ?? []).filter { ($0.expiresAtTs ?? .infinity) > now.timeIntervalSince1970 }
        let known = grants.allSatisfy { ["recurring", "purchased", "promotional"].contains($0.type) && ConnectedUsage.nonnegative($0.amountCents) != nil }
        let cap = grants.reduce(0) { $0 + $1.amountCents }
        if known, cap.isFinite, cap > 0, abs(cap - used - remaining) < 0.01 {
            let recurringOnly = grants.allSatisfy { $0.type == "recurring" }
            windows = [UsageWindow(kind: .allowance, scope: "Credits", usage: UsagePercentage(used: used, limit: cap),
                                   resetsAt: recurringOnly ? ConnectedUsage.unix(value.renewalDateTs) : nil)]
        }
        return APIKeyReading(balance: nil, windows: windows, totals: [
            ConnectedUsage.total(.creditsRemaining, remaining), ConnectedUsage.total(.creditsUsed, used)
        ].compactMap { $0 })
    }
}

enum ZaiUsage {
    private struct Response: Decodable {
        struct Payload: Decodable { var limits: [Limit]; var planName: String? }
        struct Limit: Decodable {
            var type: String
            var unit: Int?
            var number: Int?
            var percentage: Double?
            var usage: Double?
            var currentValue: Double?
            var remaining: Double?
            var nextResetTime: Double?
        }
        var success: Bool
        var code: Int
        var data: Payload
    }

    static func parse(_ data: Data, now: Date = .now) throws -> APIKeyReading {
        let value = try ConnectedUsage.decode(Response.self, from: data)
        guard value.success, value.code == 200 else { throw APIKeyClient.Failure.unreadableResponse }
        var windows: [UsageWindow] = []
        for limit in value.data.limits where ["TOKENS_LIMIT", "TIME_LIMIT", "CREDIT_LIMIT"].contains(limit.type) {
            let usage: UsagePercentage?
            if let cap = ConnectedUsage.nonnegative(limit.usage), cap > 0,
               let used = ConnectedUsage.nonnegative(limit.currentValue) ?? ConnectedUsage.nonnegative(limit.remaining).map({ max(0, cap - $0) }) {
                usage = UsagePercentage(used: used, limit: cap)
            } else if let percent = ConnectedUsage.nonnegative(limit.percentage) {
                usage = UsagePercentage(percent: percent)
            } else { throw APIKeyClient.Failure.unreadableResponse }
            var kind: UsageWindowKind = .allowance
            let multiplier = [1: 1_440, 3: 60, 5: 1, 6: 10_080][limit.unit ?? -1]
            if let number = limit.number, number > 0, number <= 10_000, let multiplier {
                kind = UsageWindowKind(durationMinutes: number * multiplier)
            }
            // This is an MCP billing marker, not a one-minute window.
            if limit.type == "TIME_LIMIT", limit.unit == 5, limit.number == 1 { kind = .monthly }
            var reset = ConnectedUsage.unix(limit.nextResetTime.map { $0 / 1_000 })
            if kind == .fiveHour, let date = reset, date.timeIntervalSince(now) > 5 * 3_600 + 60 { reset = nil }
            let scope: String? = limit.type == "TIME_LIMIT" ? "MCP" : limit.type == "CREDIT_LIMIT" ? "Credits" : nil
            let window = UsageWindow(kind: kind, scope: scope, usage: usage, resetsAt: reset)
            // SwiftUI identifiers must be unique, even if a service sends
            // duplicate entries. Keep the stricter reported quota.
            if let index = windows.firstIndex(where: { $0.id == window.id }) {
                if (usage?.value ?? 0) > (windows[index].usage?.value ?? 0) { windows[index] = window }
            } else { windows.append(window) }
        }
        guard !windows.isEmpty else { throw APIKeyClient.Failure.unreadableResponse }
        return APIKeyReading(balance: nil, windows: windows.sortedForDisplay(), planName: value.data.planName)
    }
}
