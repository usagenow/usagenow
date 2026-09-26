import Foundation

/// Where OpenCode keeps what UsageNow reads: its SQLite database in
/// `~/.local/share/opencode`.
///
/// Discovery checks that files exist and opens nothing.
struct OpenCodeEnvironment: Sendable, Equatable {
    var dataDirectory: URL
    /// The database OpenCode writes, when there is one.
    var database: URL?
    var executable: URL?
    var application: URL?

    var isInstalled: Bool { database != nil || executable != nil || application != nil }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> OpenCodeEnvironment {
        // OpenCode follows the XDG layout on macOS too.
        let dataDirectory = homeDirectory.appending(path: ".local/share/opencode", directoryHint: .isDirectory)
        let applications = [
            URL(filePath: "/Applications/OpenCode.app", directoryHint: .isDirectory),
            homeDirectory.appending(path: "Applications/OpenCode.app", directoryHint: .isDirectory),
        ]
        return OpenCodeEnvironment(
            dataDirectory: dataDirectory,
            database: database(in: dataDirectory, fileManager: fileManager),
            executable: ExecutableLocator.newest(
                among: [homeDirectory.appending(path: ".opencode/bin/opencode")]
                    + ExecutableLocator.commonCandidates(named: "opencode", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            ),
            application: applications.first { fileManager.fileExists(atPath: $0.path) }
        )
    }

    /// `opencode.db` for release builds. Other release channels write
    /// `opencode-<channel>.db`; the most recently used one is read when
    /// there's no release database.
    static func database(in directory: URL, fileManager: FileManager) -> URL? {
        let release = directory.appending(path: "opencode.db")
        if fileManager.fileExists(atPath: release.path) { return release }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let channels = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return channels
            .filter { $0.lastPathComponent.hasPrefix("opencode-") && $0.pathExtension == "db" }
            .max {
                let lhs = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return lhs < rhs
            }
    }
}
