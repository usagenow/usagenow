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
    var hasExecutable: Bool

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
        let executables = [
            homeDirectory.appending(path: ".local/bin/claude"),
            homeDirectory.appending(path: ".claude/local/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude"),
        ]
        return ClaudeCodeEnvironment(
            configDirectory: configDirectory,
            globalConfigFile: globalConfig,
            configDirectoryExists: directoryExists,
            configDirectoryIsReadable: directoryExists && fileManager.isReadableFile(atPath: configDirectory.path),
            globalConfigExists: fileManager.fileExists(atPath: globalConfig.path),
            hasExecutable: executables.contains { fileManager.isExecutableFile(atPath: $0.path) }
        )
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
            planName: ClaudePlan.displayName(organizationType: account.organizationType, rateLimitTier: account.organizationRateLimitTier)
        )
    }

    private struct GlobalConfig: Decodable {
        struct Account: Decodable {
            var organizationType: String?
            var organizationRateLimitTier: String?
        }

        var oauthAccount: Account?
    }
}

enum ClaudePlan {
    /// Plan name from the explicit organization type Claude Code caches.
    /// Unknown values return `nil`; the plan is never inferred from models.
    static func displayName(organizationType: String?, rateLimitTier: String?) -> String? {
        switch organizationType?.lowercased() {
        case "claude_pro":
            return "Pro"
        case "claude_max":
            let tier = rateLimitTier?.lowercased() ?? ""
            if tier.hasSuffix("max_20x") { return "Max 20x" }
            if tier.hasSuffix("max_5x") { return "Max 5x" }
            return "Max"
        case "claude_team":
            return "Team"
        case "claude_enterprise":
            return "Enterprise"
        default:
            return nil
        }
    }
}
