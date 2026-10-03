import Foundation

/// Where Grok Build keeps what UsageNow reads: each session's update log
/// under `~/.grok/sessions/<project>/<session>/updates.jsonl`.
///
/// Discovery checks that files exist and opens nothing. Grok Build's
/// sign-in and settings are never touched.
struct GrokBuildEnvironment: Sendable, Equatable {
    var home: URL
    var homeExists: Bool
    var executable: URL?

    var isInstalled: Bool { homeExists || executable != nil }

    var sessionsRoot: URL { home.appending(path: "sessions", directoryHint: .isDirectory) }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> GrokBuildEnvironment {
        let home = homeDirectory.appending(path: ".grok", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        return GrokBuildEnvironment(
            home: home,
            homeExists: fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue,
            executable: ExecutableLocator.newest(
                among: [homeDirectory.appending(path: ".grok/bin/grok")]
                    + ExecutableLocator.commonCandidates(named: "grok", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            )
        )
    }
}
