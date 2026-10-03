import Foundation

/// Where Qwen Code keeps what UsageNow reads: the session recordings under
/// `~/.qwen/projects/<project>/chats/<session>.jsonl`.
///
/// Discovery checks that files exist and opens nothing. Qwen Code's sign-in
/// (`~/.qwen/oauth_creds.json`) and settings are never touched.
struct QwenCodeEnvironment: Sendable, Equatable {
    var home: URL
    var homeExists: Bool
    var executable: URL?

    var isInstalled: Bool { homeExists || executable != nil }

    var sessionsRoot: URL { home.appending(path: "projects", directoryHint: .isDirectory) }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> QwenCodeEnvironment {
        let home = homeDirectory.appending(path: ".qwen", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        return QwenCodeEnvironment(
            home: home,
            homeExists: fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue,
            executable: ExecutableLocator.newest(
                among: ExecutableLocator.commonCandidates(named: "qwen", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            )
        )
    }
}
