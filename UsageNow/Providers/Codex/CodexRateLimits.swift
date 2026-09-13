import Foundation

/// Codex rate limits, from the app-server or from a session record.
///
/// Codex reports up to two windows (`primary`, `secondary`) whose lengths
/// vary by plan — an account may have only a weekly window. Windows are
/// identified by their duration, never by position.
struct CodexRateLimitSnapshot: Sendable, Equatable {
    struct Window: Sendable, Equatable {
        var usedPercent: Double
        var durationMinutes: Int?
        var resetsAt: Date?
    }

    var windows: [Window]
    var planType: String?
    /// When Codex reported these values.
    var capturedAt: Date

    /// Normalized windows that are still meaningful at `now`.
    ///
    /// Drops windows of unknown length (they can't be labeled) and windows
    /// that have reset since capture (current usage is unknown).
    func usageWindows(at now: Date) -> [UsageWindow] {
        windows.compactMap { window -> UsageWindow? in
            guard let minutes = window.durationMinutes, minutes > 0 else { return nil }
            if let resetsAt = window.resetsAt, resetsAt <= now { return nil }
            return UsageWindow(
                kind: UsageWindowKind(durationMinutes: minutes),
                usage: UsagePercentage(percent: window.usedPercent),
                resetsAt: window.resetsAt
            )
        }
        .sortedForDisplay()
    }
}

enum CodexPlan {
    /// Display name for a Codex `planType`. Unknown or ambiguous values
    /// return `nil` so no badge is shown.
    static func displayName(for planType: String?) -> String? {
        guard let planType = planType?.lowercased() else { return nil }
        switch planType {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        case "edu_plus": return "Edu Plus"
        case "edu_pro": return "Edu Pro"
        default:
            // Billing variants of a named plan, e.g. "self_serve_business_usage_based".
            if planType.hasPrefix("self_serve_business_") { return "Business" }
            if planType.hasPrefix("enterprise_") { return "Enterprise" }
            return nil
        }
    }
}

// MARK: - Wire formats

/// `account/rateLimits/read` result (camelCase, app-server protocol v2).
struct CodexAppServerRateLimitsResult: Decodable {
    struct Snapshot: Decodable {
        var primary: Window?
        var secondary: Window?
        var planType: String?
    }

    struct Window: Decodable {
        var usedPercent: Double
        var windowDurationMins: Int?
        var resetsAt: Int64?
    }

    var rateLimits: Snapshot

    func snapshot(capturedAt: Date) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            windows: [rateLimits.primary, rateLimits.secondary].compactMap { window in
                window.map {
                    .init(
                        usedPercent: $0.usedPercent,
                        durationMinutes: $0.windowDurationMins,
                        resetsAt: $0.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                }
            },
            planType: rateLimits.planType,
            capturedAt: capturedAt
        )
    }
}

/// `rate_limits` inside a session `token_count` event (snake_case).
struct CodexRecordedRateLimits: Decodable {
    struct Window: Decodable {
        var used_percent: Double?
        var window_minutes: Int?
        var resets_at: Int64?
        /// Older Codex versions: seconds until reset, relative to the event.
        var resets_in_seconds: Int64?
    }

    var primary: Window?
    var secondary: Window?
    var plan_type: String?

    func snapshot(capturedAt: Date) -> CodexRateLimitSnapshot? {
        let windows = [primary, secondary].compactMap { window -> CodexRateLimitSnapshot.Window? in
            guard let window, let used = window.used_percent else { return nil }
            let resetsAt = window.resets_at.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ?? window.resets_in_seconds.map { capturedAt.addingTimeInterval(TimeInterval($0)) }
            return .init(usedPercent: used, durationMinutes: window.window_minutes, resetsAt: resetsAt)
        }
        guard !windows.isEmpty else { return nil }
        return CodexRateLimitSnapshot(windows: windows, planType: plan_type, capturedAt: capturedAt)
    }
}
