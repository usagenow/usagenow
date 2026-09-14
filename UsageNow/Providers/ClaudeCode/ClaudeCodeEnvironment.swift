import Foundation

/// Where Claude Code keeps its data on this Mac. Discovery only checks file
/// metadata; credentials in the keychain are never touched here.
struct ClaudeCodeEnvironment: Sendable, Equatable {
    /// `$CLAUDE_CONFIG_DIR`, or `~/.claude`.
    var configDirectory: URL
    /// Global settings, including the cached account profile
    /// (`~/.claude.json`, or `.claude.json` inside `$CLAUDE_CONFIG_DIR`).
    var globalConfigFile: URL
    var configDirectoryExists: Bool
    var configDirectoryIsReadable: Bool
    var globalConfigExists: Bool
    /// The Claude Code CLI. Only its presence is used, to tell that Claude Code is installed.
    var executable: URL?

    var hasExecutable: Bool { executable != nil }

    var isInstalled: Bool { configDirectoryExists || globalConfigExists || hasExecutable }

    var sessionRoots: [URL] { [configDirectory.appending(path: "projects")] }

    static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ClaudeCodeEnvironment {
        let fileManager = FileManager.default
        let customDirectory = environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        let configDirectory = customDirectory ?? homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        let globalConfig = customDirectory.map { $0.appending(path: ".claude.json") } ?? homeDirectory.appending(path: ".claude.json")

        var isDirectory: ObjCBool = false
        let directoryExists = fileManager.fileExists(atPath: configDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue
        return ClaudeCodeEnvironment(
            configDirectory: configDirectory,
            globalConfigFile: globalConfig,
            configDirectoryExists: directoryExists,
            configDirectoryIsReadable: directoryExists && fileManager.isReadableFile(atPath: configDirectory.path),
            globalConfigExists: fileManager.fileExists(atPath: globalConfig.path),
            executable: locateExecutable(homeDirectory: homeDirectory)
        )
    }

    /// Common install locations plus Claude Code's own: the local install
    /// and native installs, which keep one binary per version.
    static func locateExecutable(homeDirectory: URL, fileManager: FileManager = .default) -> URL? {
        var candidates = ExecutableLocator.commonCandidates(named: "claude", homeDirectory: homeDirectory, fileManager: fileManager)
        candidates.append(homeDirectory.appending(path: ".claude/local/claude"))
        let versions = homeDirectory.appending(path: ".local/share/claude/versions")
        if let installed = try? fileManager.contentsOfDirectory(atPath: versions.path) {
            candidates += installed.map { versions.appending(path: $0) }
        }
        return ExecutableLocator.newest(among: candidates, fileManager: fileManager)
    }
}

/// The signed-in account as cached by Claude Code in its global config.
///
/// Only a few fields of `oauthAccount` are decoded; project lists and
/// identifiers in the same file are ignored.
struct ClaudeAccountProfile: Sendable, Equatable {
    var isSignedIn: Bool
    var planName: String?

    static let signedOut = ClaudeAccountProfile(isSignedIn: false, planName: nil)

    static func read(from file: URL) -> ClaudeAccountProfile {
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(GlobalConfig.self, from: data),
              let account = config.oauthAccount else { return .signedOut }
        return ClaudeAccountProfile(
            isSignedIn: true,
            planName: ClaudePlan.displayName(
                organizationType: account.organizationType,
                rateLimitTier: account.organizationRateLimitTier,
                seatTier: account.seatTier
            )
        )
    }

    private struct GlobalConfig: Decodable {
        /// Only plan fields. Names, email addresses, and organization or
        /// account identifiers in the same object are never decoded.
        struct Account: Decodable {
            var organizationType: String?
            var organizationRateLimitTier: String?
            /// The signed-in member's seat on a Team or Enterprise plan.
            var seatTier: String?
        }

        var oauthAccount: Account?
    }
}

enum ClaudePlan {
    /// Seat tiers shown next to a Team or Enterprise plan. Anything else
    /// shows the plan alone rather than a guess.
    private static let seatNames = ["standard": "Standard", "premium": "Premium"]

    /// Plan name from the explicit organization type Claude Code caches.
    /// Unknown values return `nil`; the plan is never inferred from models.
    static func displayName(organizationType: String?, rateLimitTier: String?, seatTier: String? = nil) -> String? {
        switch organizationType?.lowercased() {
        case "claude_pro":
            return "Pro"
        case "claude_max":
            let tier = rateLimitTier?.lowercased() ?? ""
            if tier.hasSuffix("max_20x") { return "Max 20x" }
            if tier.hasSuffix("max_5x") { return "Max 5x" }
            return "Max"
        case "claude_team":
            return withSeat("Team", seatTier)
        case "claude_enterprise":
            return withSeat("Enterprise", seatTier)
        default:
            return nil
        }
    }

    /// "Team · Premium". Accepts "premium" as well as a prefixed "team_premium".
    private static func withSeat(_ plan: String, _ seatTier: String?) -> String {
        guard let seat = seatTier?.lowercased().split(separator: "_").last.map(String.init),
              let seatName = seatNames[seat] else { return plan }
        return "\(plan) · \(seatName)"
    }
}
