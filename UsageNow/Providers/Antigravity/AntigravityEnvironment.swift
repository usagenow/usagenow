import Foundation

/// Where Antigravity CLI (`agy`) lives on this Mac. Discovery reads file
/// metadata only.
struct AntigravityEnvironment: Sendable, Equatable {
    /// `~/.gemini/antigravity-cli`.
    var home: URL
    var homeExists: Bool
    var executable: URL?

    var isInstalled: Bool { homeExists || executable != nil }

    static func discover(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> AntigravityEnvironment {
        let fileManager = FileManager.default
        let home = homeDirectory.appending(path: ".gemini/antigravity-cli", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        return AntigravityEnvironment(
            home: home,
            homeExists: fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue,
            executable: ExecutableLocator.newest(
                among: ExecutableLocator.commonCandidates(named: "agy", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            )
        )
    }
}
