import Foundation

/// Where Kiro keeps what UsageNow reads on this Mac.
///
/// - `~/.kiro/sessions` — the agent's session records, including the credits
///   each prompt turn used.
/// - `~/Library/Application Support/Kiro/logs` — the IDE's logs, one folder
///   per launch. Kiro writes its own usage-limits answer there.
///
/// Discovery checks that these exist. It opens nothing, and there is no Kiro
/// credential anywhere in what UsageNow reads.
struct KiroEnvironment: Sendable, Equatable {
    var home: URL
    var homeExists: Bool
    var logsRoot: URL
    var application: URL?

    var isInstalled: Bool { homeExists || application != nil }

    var sessionsRoot: URL { home.appending(path: "sessions", directoryHint: .isDirectory) }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> KiroEnvironment {
        let home = homeDirectory.appending(path: ".kiro", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        let homeExists = fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue

        let applications = [
            URL(filePath: "/Applications/Kiro.app", directoryHint: .isDirectory),
            homeDirectory.appending(path: "Applications/Kiro.app", directoryHint: .isDirectory),
        ]

        return KiroEnvironment(
            home: home,
            homeExists: homeExists,
            logsRoot: homeDirectory.appending(path: "Library/Application Support/Kiro/logs", directoryHint: .isDirectory),
            application: applications.first { fileManager.fileExists(atPath: $0.path) }
        )
    }
}
