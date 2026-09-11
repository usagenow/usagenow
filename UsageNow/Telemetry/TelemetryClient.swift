import Foundation

/// Receives explicitly defined, privacy-safe events.
///
/// Privacy boundary: a telemetry client never has access to `UsageStore`,
/// provider snapshots, or any provider data. It can only receive a
/// `TelemetryEvent`, and the payload built from it carries only the fields
/// in `TelemetryPayload`.
///
/// Telemetry never includes token counts, quota percentages, reset times,
/// model names, plan tiers, project or session names, file paths, prompts,
/// conversation text, credentials, or provider account identifiers.
protocol TelemetryClient: Sendable {
    /// Must never throw, block, or surface errors to the user.
    func send(_ event: TelemetryEvent) async
}

/// Every event UsageNow may report. Adding one is a privacy decision —
/// review it as one.
enum TelemetryEvent: String, Sendable, CaseIterable {
    /// First report from this installation.
    case install
    /// The app was used on a given day. At most once per day.
    case appActive = "app_active"
    /// First report after the app version changed.
    case appUpdated = "app_updated"
    /// Codex is installed. A yes, never anything about its usage.
    case codexDetected = "codex_detected"
    /// Claude Code is installed. A yes, never anything about its usage.
    case claudeDetected = "claude_detected"

    /// `nil` for providers with no integration yet — nothing to report.
    static func detected(_ provider: ProviderID) -> TelemetryEvent? {
        switch provider {
        case .codex: .codexDetected
        case .claudeCode: .claudeDetected
        default: nil
        }
    }
}

/// The complete request body. Nothing else is ever sent.
/// Country is resolved server-side from the request; IP addresses and
/// location aren't part of the payload.
struct TelemetryPayload: Codable, Equatable, Sendable {
    var event: String
    var installationID: String
    var appVersion: String
    var build: String
    var macOSVersion: String
    var architecture: String
    /// ISO 8601.
    var timestamp: String

    enum CodingKeys: String, CodingKey {
        case event
        case installationID = "installation_id"
        case appVersion = "app_version"
        case build
        case macOSVersion = "macos_version"
        case architecture
        case timestamp
    }

    init(event: TelemetryEvent, installationID: UUID, environment: TelemetryEnvironment, date: Date) {
        self.event = event.rawValue
        self.installationID = installationID.uuidString.lowercased()
        self.appVersion = environment.appVersion
        self.build = environment.build
        self.macOSVersion = environment.macOSVersion
        self.architecture = environment.architecture
        self.timestamp = date.formatted(Date.ISO8601FormatStyle())
    }
}

/// Non-identifying facts about the app and OS.
struct TelemetryEnvironment: Sendable, Equatable {
    var appVersion: String
    var build: String
    var macOSVersion: String
    var architecture: String

    static var current: TelemetryEnvironment {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return TelemetryEnvironment(
            appVersion: AppInfo.version,
            build: AppInfo.build,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            architecture: architecture
        )
    }
}
