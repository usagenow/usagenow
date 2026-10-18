import Foundation

/// Only normalized quota leaves the reader. No license IDs, usernames,
/// machine identifiers, or raw XML/log text enter application state.
struct JetBrainsQuota: Sendable, Equatable {
    let window: UsageWindow
    let expiresAt: Date?
    var observedAt: Date

    func windows(at date: Date) -> [UsageWindow] {
        var result = [window].asOf(date)
        if let expiresAt, expiresAt <= date { result[0].usage = nil }
        return result
    }

    /// JetBrains has used JSON numbers, decimal strings, and wrapped
    /// amounts. Boolean values must never become zero/one quota counters.
    struct Amount: Decodable {
        let value: Double
        private enum CodingKeys: String, CodingKey { case amount }
        init(from decoder: any Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let number = try? single.decode(Double.self) { value = number }
            else if let string = try? single.decode(String.self), let number = Double(string) { value = number }
            else { value = try decoder.container(keyedBy: CodingKeys.self).decode(Amount.self, forKey: .amount).value }
        }
    }

    struct Counters: Decodable {
        let current: Amount?
        let maximum: Amount?
        private enum CodingKeys: String, CodingKey { case current, maximum }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            current = try? c.decode(Amount.self, forKey: .current)
            maximum = try? c.decode(Amount.self, forKey: .maximum)
        }

        var percentage: UsagePercentage? {
            guard let used = current?.value, let total = maximum?.value else { return nil }
            return JetBrainsQuota.percentage(used: used, total: total)
        }
    }

    struct Payload: Decodable {
        let type: String?
        let tariffQuota: Counters?
        let total: Counters
        let expiresAt: Date?
        private enum CodingKeys: String, CodingKey { case type, tariffQuota, until }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decodeIfPresent(String.self, forKey: .type)
            tariffQuota = try? c.decode(Counters.self, forKey: .tariffQuota)
            total = try Counters(from: decoder)
            if let string = try? c.decode(String.self, forKey: .until) { expiresAt = JetBrainsQuota.date(string) }
            else if let milliseconds = try? c.decode(Double.self, forKey: .until), milliseconds.isFinite, milliseconds > 0 {
                expiresAt = Date(timeIntervalSince1970: milliseconds / 1_000)
            } else { expiresAt = nil }
        }

        func quota(observedAt: Date, reset: Date?, allowsTotal: Bool) -> JetBrainsQuota? {
            guard type == nil || type == "Available" else { return nil }
            let monthly = tariffQuota?.percentage
            guard let usage = monthly ?? (allowsTotal ? total.percentage : nil) else { return nil }
            return JetBrainsQuota(
                window: UsageWindow(kind: monthly == nil ? .allowance : .monthly, usage: usage,
                                    // A top-up-inclusive total does not reset when the monthly tariff refills.
                                    resetsAt: monthly == nil ? nil : reset),
                expiresAt: expiresAt, observedAt: observedAt
            )
        }
    }

    static func percentage(used: Double, total: Double) -> UsagePercentage? {
        guard used.isFinite, total.isFinite, used >= 0, total > 0 else { return nil }
        return UsagePercentage(percent: used / total * 100)
    }

    static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601)) ?? (try? Date(text, strategy: .iso8601.time(includingFractionalSeconds: true)))
    }
}
