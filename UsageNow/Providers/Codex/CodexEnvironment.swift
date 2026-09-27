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
            executable: executableCandidates(homeDirectory: homeDirectory, fileManager: fileManager).first { fileManager.isExecutableFile(atPath: $0.path) },
            homeExists: homeExists,
            homeIsReadable: homeExists && fileManager.isReadableFile(atPath: home.path),
            hasAuthFile: fileManager.fileExists(atPath: home.appending(path: "auth.json").path)
        )
    }

    /// Well-known install locations, preferring the native binary bundled
    /// with the Codex or ChatGPT app. Apps launched from Finder don't inherit
    /// the shell's `PATH`, so it isn't searched.
    static func executableCandidates(homeDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        let applicationDirectories = [URL(filePath: "/Applications"), homeDirectory.appending(path: "Applications")]
        // ChatGPT 26.9 moved the bundled CLI from Resources/codex into
        // Resources/codex-cli/bin; both layouts are still in use.
        let bundled = applicationDirectories.flatMap { directory in
            ["Codex.app", "ChatGPT.app"].flatMap { app in
                ["Contents/Resources/codex", "Contents/Resources/codex-cli/bin/codex"].map { directory.appending(path: "\(app)/\($0)") }
            }
        }
        let installed = [
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
            homeDirectory.appending(path: ".local/bin/codex"),
        ]
        return bundled + installed + ExecutableLocator.commonCandidates(named: "codex", homeDirectory: homeDirectory, fileManager: fileManager)
            + editorExtensionCandidates(homeDirectory: homeDirectory, fileManager: fileManager)
    }

    /// The CLI bundled with the Codex extension for VS Code and the editors
    /// built on it, for people who use Codex only there. Newest version first.
    static func editorExtensionCandidates(homeDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        #if arch(arm64)
        let platform = "macos-aarch64"
        #else
        let platform = "macos-x86_64"
        #endif
        let editors = [".vscode", ".cursor", ".windsurf", ".kiro", ".qoder"]
        return editors.flatMap { editor -> [URL] in
            let extensions = homeDirectory.appending(path: "\(editor)/extensions", directoryHint: .isDirectory)
            let names = (try? fileManager.contentsOfDirectory(atPath: extensions.path)) ?? []
            return names
                .filter { $0.hasPrefix("openai.chatgpt-") }
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { extensions.appending(path: "\($0)/bin/\(platform)/codex") }
        }
    }
}
