import Foundation

/// Kiro's monthly credit limit, as Kiro itself last received it.
///
/// Kiro doesn't expose its limits through anything public. The IDE does log
/// every call its agent makes, and one of those is `GetUsageLimitsCommand`,
/// logged with the answer in full: plan, credits used, the limit, and when it
/// resets. UsageNow reads that line from the newest logs. It makes no request
/// of its own and has no credential to make one with.
///
/// The same answer also names the account (`userInfo`, `profileArn`). Those
/// fields aren't declared below, so they're never decoded.
///
/// A log isn't an API: if Kiro stops writing this line, limits disappear and
/// the section says to open Kiro, rather than showing a number that's wrong.
struct KiroUsageLimits: Sendable, Equatable {
    var planName: String?
    var creditsUsed: Double
    var creditsLimit: Double
    var resetsAt: Date?
    /// When Kiro logged this answer.
    var observedAt: Date

    var window: UsageWindow {
        UsageWindow(
            kind: .monthly,
            usage: UsagePercentage(used: creditsUsed, limit: creditsLimit),
            resetsAt: resetsAt
        )
    }
}

enum KiroUsageLimitsReader {
    /// Kiro starts a log folder per launch; the answer is in a recent one.
    static let launchesToSearch = 5
    /// A client log is small; this is a guard, not an expectation.
    static let maxBytesPerLog: UInt64 = 4 << 20

    static func latest(in logsRoot: URL, fileManager: FileManager = .default) -> KiroUsageLimits? {
        let launches = (try? fileManager.contentsOfDirectory(at: logsRoot, includingPropertiesForKeys: nil)) ?? []
        let recent = launches
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(launchesToSearch)

        var newest: KiroUsageLimits?
        for launch in recent {
            for log in clientLogs(in: launch, fileManager: fileManager) {
                guard let lines = try? JSONLReader.trailingLines(in: log, maxBytes: maxBytesPerLog) else { continue }
                for line in lines {
                    guard let limits = KiroUsageLimitsParser.parse(line) else { continue }
                    if limits.observedAt >= (newest?.observedAt ?? .distantPast) { newest = limits }
                }
            }
            // Launch folders sort by time, so a hit in a newer one wins.
            if newest != nil { break }
        }
        return newest
    }

    /// `window*/exthost/kiro.kiroAgent/q-client.log` — one per window.
    private static func clientLogs(in launch: URL, fileManager: FileManager) -> [URL] {
        let windows = (try? fileManager.contentsOfDirectory(at: launch, includingPropertiesForKeys: nil)) ?? []
        return windows
            .filter { $0.lastPathComponent.hasPrefix("window") }
            .map { $0.appending(path: "exthost/kiro.kiroAgent/q-client.log") }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }
}

enum KiroUsageLimitsParser {
    private static let marker = Data(#""GetUsageLimitsCommand""#.utf8)

    /// Parses one log line: `2026-09-17 14:51:46.957 [info] { … }`.
    static func parse(_ line: Data, now: Date = .now) -> KiroUsageLimits? {
        guard line.contains(marker),
              let brace = line.firstIndex(of: UInt8(ascii: "{")),
              let observedAt = timestamp(String(decoding: line[line.startIndex..<brace], as: UTF8.self)),
              let record = try? JSONDecoder().decode(Line.self, from: line[brace...]),
              record.commandName == "GetUsageLimitsCommand",
              let output = record.output,
              let credits = output.usageBreakdownList?.first(where: { $0.resourceType == "CREDIT" })
                  ?? output.usageBreakdownList?.first
        else { return nil }

        var used = credits.currentUsageWithPrecision ?? credits.currentUsage ?? 0
        var limit = credits.usageLimitWithPrecision ?? credits.usageLimit ?? 0

        // A trial or bonus adds credits only while it's active. An expired
        // trial is still reported, fully used — counting it would show an
        // untouched plan as exhausted.
        if let trial = credits.freeTrialInfo, trial.freeTrialStatus == "ACTIVE" {
            used += trial.currentUsageWithPrecision ?? trial.currentUsage ?? 0
            limit += trial.usageLimitWithPrecision ?? trial.usageLimit ?? 0
        }
        for bonus in credits.bonuses ?? [] where isActive(bonus, now: now) {
            used += bonus.currentUsageWithPrecision ?? bonus.currentUsage ?? 0
            limit += bonus.usageLimitWithPrecision ?? bonus.usageLimit ?? 0
        }
        guard limit > 0 else { return nil }

        return KiroUsageLimits(
            planName: output.subscriptionInfo?.subscriptionTitle.flatMap(planName(from:)),
            creditsUsed: used,
            creditsLimit: limit,
            resetsAt: SessionTimestamp.parse(credits.nextDateReset ?? output.nextDateReset),
            observedAt: observedAt
        )
    }

    /// "KIRO FREE" → "Free", "KIRO PRO+" → "Pro+".
    static func planName(from title: String) -> String? {
        var name = title.trimmingCharacters(in: .whitespaces)
        // The product name alone, "KIRO", names no plan.
        if name.uppercased() == "KIRO" { return nil }
        if name.uppercased().hasPrefix("KIRO ") { name = String(name.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        guard !name.isEmpty else { return nil }
        return name.lowercased().capitalized
    }

    private static func isActive(_ bonus: Line.Output.Bonus, now: Date) -> Bool {
        if let status = bonus.status { return status == "ACTIVE" }
        guard let expiry = SessionTimestamp.parse(bonus.expiresAt) else { return false }
        return expiry > now
    }

    private static let timestampFormat: Date.ParseStrategy = Date.ParseStrategy(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .current
    )

    /// The log writes local time without a zone.
    private static func timestamp(_ prefix: String) -> Date? {
        let text = prefix.trimmingCharacters(in: .whitespaces)
        guard text.count >= 23 else { return nil }
        return try? Date(String(text.prefix(23)), strategy: timestampFormat)
    }

    private struct Line: Decodable {
        struct Output: Decodable {
            struct Breakdown: Decodable {
                var resourceType: String?
                var currentUsage: Double?
                var currentUsageWithPrecision: Double?
                var usageLimit: Double?
                var usageLimitWithPrecision: Double?
                var nextDateReset: String?
                var freeTrialInfo: Trial?
                var bonuses: [Bonus]?
            }

            struct Trial: Decodable {
                var freeTrialStatus: String?
                var currentUsage: Double?
                var currentUsageWithPrecision: Double?
                var usageLimit: Double?
                var usageLimitWithPrecision: Double?
            }

            struct Bonus: Decodable {
                var status: String?
                var expiresAt: String?
                var currentUsage: Double?
                var currentUsageWithPrecision: Double?
                var usageLimit: Double?
                var usageLimitWithPrecision: Double?
            }

            struct Subscription: Decodable {
                var subscriptionTitle: String?
            }

            var nextDateReset: String?
            var usageBreakdownList: [Breakdown]?
            var subscriptionInfo: Subscription?
        }

        var commandName: String?
        var output: Output?
    }
}
