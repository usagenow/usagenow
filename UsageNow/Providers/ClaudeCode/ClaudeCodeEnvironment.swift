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
    /// The Claude Code CLI, used only to ask it to refresh its own sign-in.
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

    /// Well-known install locations. Apps launched from Finder don't inherit
    /// the shell's `PATH`, so it isn't searched.
    ///
    /// A Mac often has more than one copy — a native install left behind
    /// after switching to npm, or one per Node version — so the most
    /// recently installed binary wins rather than the first one found.
    static func locateExecutable(homeDirectory: URL, fileManager: FileManager = .default) -> URL? {
        var candidates = [
            homeDirectory.appending(path: ".local/bin/claude"),
            homeDirectory.appending(path: ".claude/local/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude"),
        ]
        // Native installs keep one binary per version.
        let versions = homeDirectory.appending(path: ".local/share/claude/versions")
        if let installed = try? fileManager.contentsOfDirectory(atPath: versions.path) {
            candidates += installed.sorted(by: >).map { versions.appending(path: $0) }
        }
        // npm installs, including one per Node version under nvm.
        let nodeVersions = homeDirectory.appending(path: ".nvm/versions/node")
        if let nodes = try? fileManager.contentsOfDirectory(atPath: nodeVersions.path) {
            candidates += nodes.sorted(by: >).map { nodeVersions.appending(path: "\($0)/bin/claude") }
        }
        let installed = candidates.filter { fileManager.isExecutableFile(atPath: $0.path) }
        return installed.max { installDate(of: $0, fileManager) < installDate(of: $1, fileManager) }
    }

    /// When the binary a candidate points at was written; symlinks are followed.
    private static func installDate(of executable: URL, _ fileManager: FileManager) -> Date {
        let target = executable.resolvingSymlinksInPath()
        return (try? fileManager.attributesOfItem(atPath: target.path)[.modificationDate] as? Date) ?? .distantPast
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
