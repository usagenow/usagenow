import Foundation

/// Parses `RetrieveUserQuotaSummary` defensively.
///
/// The summary lists groups of models ("Gemini Models", "Claude and GPT
/// Models") that share limits, each with buckets such as `gemini-5h` or
/// `3p-weekly`. Antigravity CLI wraps it as `{"response": {"groups": …}}`.
/// A bucket becomes a window only when its length can be read from its
/// identifier or name and it states a remaining fraction; the group's name
/// becomes the window's scope. Anything else is skipped rather than guessed.
enum AntigravityQuotaParser {
    static func windows(from data: Data) -> [UsageWindow]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let summary = object["quotaSummary"] as? [String: Any] ?? object["response"] as? [String: Any] ?? object
        guard let groups = summary["groups"] as? [[String: Any]] else { return nil }

        var windows: [UsageWindow] = []
        for group in groups {
            let scope = scopeName(group["displayName"] as? String)
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard (bucket["disabled"] as? Bool) != true else { continue }
                let remaining = bucket["remaining"] as? [String: Any] ?? [:]
                guard let fraction = number(bucket["remainingFraction"] ?? remaining["remainingFraction"]),
                      let kind = kind(for: [bucket["bucketId"], bucket["displayName"]].compactMap { $0 as? String }.joined(separator: " ")) else { continue }
                windows.append(UsageWindow(
                    kind: kind,
                    scope: scope,
                    usage: UsagePercentage(percent: (1 - min(max(fraction, 0), 1)) * 100),
                    resetsAt: date(from: bucket["resetTime"] ?? remaining["resetTime"])
                ))
            }
        }
        return windows.sortedForDisplay()
    }

    /// "Gemini Models" → "Gemini"; "Claude and GPT Models" → "Claude and GPT".
    static func scopeName(_ displayName: String?) -> String? {
        guard var name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if name.lowercased().hasSuffix(" models") { name = String(name.dropLast(" models".count)) }
        return name.isEmpty ? nil : name
    }

    /// The window length a bucket names, e.g. "weekly", "daily", "5-hour", "5h".
    static func kind(for text: String) -> UsageWindowKind? {
        let lowered = text.lowercased()
        if lowered.contains("week") { return .weekly }
        if lowered.contains("daily") || lowered.contains("24h") { return UsageWindowKind(durationMinutes: 24 * 60) }
        if let hours = firstNumber(in: lowered, before: ["-hour", " hour", "hour", "h"]) { return UsageWindowKind(durationMinutes: hours * 60) }
        return nil
    }

    private static func firstNumber(in text: String, before units: [String]) -> Int? {
        for unit in units {
            guard let range = text.range(of: "(\\d+)\(NSRegularExpression.escapedPattern(for: unit))\\b", options: .regularExpression) else { continue }
            let digits = text[range].prefix { $0.isNumber }
            if let value = Int(digits), value > 0 { return value }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    /// RFC 3339 strings, or epoch seconds or milliseconds.
    static func date(from value: Any?) -> Date? {
        switch value {
        case let string as String:
            if let date = SessionTimestamp.parse(string) { return date }
            return Double(string).flatMap(epochDate)
        case let number as NSNumber:
            return epochDate(number.doubleValue)
        default:
            return nil
        }
    }

    private static func epochDate(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 1e12 ? value / 1000 : value)
    }
}
