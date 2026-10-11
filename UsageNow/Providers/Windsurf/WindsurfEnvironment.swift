import Foundation

/// Where Windsurf keeps what UsageNow reads: the editor's own settings
/// database, in which it caches the plan and limits it last received.
///
/// Discovery checks that the app or the database exists and opens nothing.
struct WindsurfEnvironment: Sendable, Equatable {
    var database: URL
    var databaseExists: Bool
    var application: URL?

    var isInstalled: Bool { databaseExists || application != nil }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> WindsurfEnvironment {
        let database = homeDirectory.appending(path: "Library/Application Support/Windsurf/User/globalStorage/state.vscdb")
        let applications = [
            URL(filePath: "/Applications/Windsurf.app", directoryHint: .isDirectory),
            homeDirectory.appending(path: "Applications/Windsurf.app", directoryHint: .isDirectory),
        ]
        return WindsurfEnvironment(
            database: database,
            databaseExists: fileManager.fileExists(atPath: database.path),
            application: applications.first { fileManager.fileExists(atPath: $0.path) }
        )
    }
}
