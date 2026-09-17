import Foundation

/// Where Warp keeps what UsageNow reads: its local SQLite database.
///
/// Discovery checks that the app or the database exists and opens nothing.
struct WarpEnvironment: Sendable, Equatable {
    var database: URL
    var databaseExists: Bool
    var application: URL?

    var isInstalled: Bool { databaseExists || application != nil }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> WarpEnvironment {
        let database = homeDirectory.appending(
            path: "Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite"
        )
        let applications = [
            URL(filePath: "/Applications/Warp.app", directoryHint: .isDirectory),
            homeDirectory.appending(path: "Applications/Warp.app", directoryHint: .isDirectory),
        ]
        return WarpEnvironment(
            database: database,
            databaseExists: fileManager.fileExists(atPath: database.path),
            application: applications.first { fileManager.fileExists(atPath: $0.path) }
        )
    }
}
