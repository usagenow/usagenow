import OSLog

/// OSLog categories. Never log tokens, credentials, prompts, conversation
/// content, source code, or file paths from `~/.codex` / `~/.claude`.
/// Interpolated values default to `.private` in OSLog; mark only
/// enum-like, non-identifying values as `.public`.
enum Log {
    private static let subsystem = "com.usagenow.UsageNow"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let provider = Logger(subsystem: subsystem, category: "provider")
    static let telemetry = Logger(subsystem: subsystem, category: "telemetry")
}
