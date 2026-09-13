import Foundation

/// Where Gemini CLI keeps its data on this Mac (`~/.gemini`).
///
/// Discovery reads file metadata and one setting — which kind of sign-in
/// Gemini CLI is configured for. Credential files are checked for
/// existence only and never opened.
struct GeminiEnvironment: Sendable, Equatable {
    static let oauthCredentialsFileName = "oauth_creds.json"

    var home: URL
    var homeExists: Bool
    var homeIsReadable: Bool
    /// The configured sign-in method, e.g. "oauth-personal" or "gemini-api-key".
    /// A setting name, never a credential.
    var authType: String?
    /// Whether Gemini CLI has saved a Google sign-in. Existence only.
    var hasOAuthCredentialsFile: Bool
    var executable: URL?

    var isInstalled: Bool { homeExists || executable != nil }

    var isSignedIn: Bool { authType != nil || hasOAuthCredentialsFile }

    /// Gemini CLI records sessions under `tmp/<project>/chats/`.
    var sessionRoots: [URL] { [home.appending(path: "tmp", directoryHint: .isDirectory)] }

    static func discover(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> GeminiEnvironment {
        let fileManager = FileManager.default
        let home = homeDirectory.appending(path: ".gemini", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue
        return GeminiEnvironment(
            home: home,
            homeExists: exists,
            homeIsReadable: exists && fileManager.isReadableFile(atPath: home.path),
            authType: exists ? GeminiSettings.authType(in: home.appending(path: "settings.json")) : nil,
            hasOAuthCredentialsFile: exists && fileManager.fileExists(atPath: home.appending(path: oauthCredentialsFileName).path),
            executable: ExecutableLocator.newest(
                among: ExecutableLocator.commonCandidates(named: "gemini", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            )
        )
    }
}

/// The one setting UsageNow reads from Gemini CLI's `settings.json`.
enum GeminiSettings {
    static func authType(in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return nil }
        let type = settings.security?.auth?.selectedType ?? settings.selectedAuthType
        return type?.isEmpty == false ? type : nil
    }

    private struct Settings: Decodable {
        struct Security: Decodable {
            struct Auth: Decodable {
                var selectedType: String?
            }

            var auth: Auth?
        }

        var security: Security?
        /// Where older versions kept it.
        var selectedAuthType: String?
    }
}
