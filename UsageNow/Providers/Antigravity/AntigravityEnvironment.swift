import Foundation

/// Where Antigravity CLI (`agy`) keeps its data on this Mac.
///
/// Discovery reads file metadata and whether a saved sign-in exists — the
/// keychain item's attributes, never its secret, so it never shows a prompt.
struct AntigravityEnvironment: Sendable, Equatable {
    /// The keychain service `agy` saves its Google sign-in under.
    static let keychainService = "gemini"

    /// `~/.gemini/antigravity-cli`.
    var home: URL
    var homeExists: Bool
    var executable: URL?
    var hasSavedSignIn: Bool

    var isInstalled: Bool { homeExists || executable != nil }

    static func discover(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> AntigravityEnvironment {
        let fileManager = FileManager.default
        let home = homeDirectory.appending(path: ".gemini/antigravity-cli", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue
        return AntigravityEnvironment(
            home: home,
            homeExists: exists,
            executable: ExecutableLocator.newest(
                among: ExecutableLocator.commonCandidates(named: "agy", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            ),
            hasSavedSignIn: KeychainItem.modificationDate(service: keychainService) != nil
        )
    }
}
