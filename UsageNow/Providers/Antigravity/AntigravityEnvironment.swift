import Foundation

/// Where Antigravity CLI (`agy`) keeps its data on this Mac.
///
/// Discovery reads file metadata, the project identifier `agy` caches, and
/// whether a saved sign-in exists — the keychain item's attributes, never
/// its secret, so it never shows a prompt.
struct AntigravityEnvironment: Sendable, Equatable {
    /// The keychain service `agy` saves its Google sign-in under.
    static let keychainService = "gemini"

    /// `~/.gemini/antigravity-cli`.
    var home: URL
    var homeExists: Bool
    var executable: URL?
    /// The Cloud Code project `agy` uses, from its cache. Not a credential.
    var projectID: String?
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
            projectID: exists ? projectID(in: home) : nil,
            hasSavedSignIn: KeychainItem.modificationDate(service: keychainService) != nil
        )
    }

    /// `cache/default_project_id.txt`, when it holds a plausible project identifier.
    static func projectID(in home: URL) -> String? {
        guard let data = try? Data(contentsOf: home.appending(path: "cache/default_project_id.txt")),
              data.count < 256,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }) else { return nil }
        return text
    }
}
