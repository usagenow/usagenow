import Foundation

/// Where Codex lives on this Mac. Discovery only checks file metadata.
struct CodexEnvironment: Sendable, Equatable {
    /// `$CODEX_HOME`, or `~/.codex`.
    var home: URL
    /// The official Codex CLI, used to run `codex app-server`.
    var executable: URL?
    var homeExists: Bool
    var homeIsReadable: Bool
    /// Whether `auth.json` exists. Its contents — credentials — are never read.
    var hasAuthFile: Bool

    var isInstalled: Bool { homeExists || executable != nil }

    var sessionRoots: [URL] {
        [home.appending(path: "sessions"), home.appending(path: "archived_sessions")]
    }

    static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CodexEnvironment {
        let fileManager = FileManager.default
        let home = environment["CODEX_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        let homeExists = fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue
        return CodexEnvironment(
            home: home,
            executable: executableCandidates(homeDirectory: homeDirectory).first { fileManager.isExecutableFile(atPath: $0.path) },
            homeExists: homeExists,
            homeIsReadable: homeExists && fileManager.isReadableFile(atPath: home.path),
            hasAuthFile: fileManager.fileExists(atPath: home.appending(path: "auth.json").path)
        )
    }

    /// Well-known install locations, preferring the native binary bundled
    /// with the Codex app. Apps launched from Finder don't inherit the
    /// shell's `PATH`, so it isn't searched.
    static func executableCandidates(homeDirectory: URL) -> [URL] {
        let applicationDirectories = [URL(filePath: "/Applications"), homeDirectory.appending(path: "Applications")]
        let bundled = applicationDirectories.flatMap { directory in
            ["Codex.app", "ChatGPT.app"].map { directory.appending(path: "\($0)/Contents/Resources/codex") }
        }
        let installed = [
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
            homeDirectory.appending(path: ".local/bin/codex"),
        ]
        return bundled + installed
    }
}
