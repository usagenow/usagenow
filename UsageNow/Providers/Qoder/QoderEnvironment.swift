import Foundation

/// Where Qoder keeps what UsageNow reads: the transcripts its agent writes
/// under `~/.qoder/projects`, whether it runs in the Qoder app or as
/// `qodercli`.
///
/// Discovery checks that files exist and opens nothing. Qoder's sign-in
/// (`~/.qoder/.auth`, the app's `auth.v1.dat`) is never touched.
struct QoderEnvironment: Sendable, Equatable {
    var home: URL
    var homeExists: Bool
    var application: URL?
    var executable: URL?

    var isInstalled: Bool { homeExists || application != nil || executable != nil }

    var sessionsRoot: URL { home.appending(path: "projects", directoryHint: .isDirectory) }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> QoderEnvironment {
        let home = homeDirectory.appending(path: ".qoder", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        let applications = [
            URL(filePath: "/Applications/Qoder.app", directoryHint: .isDirectory),
            homeDirectory.appending(path: "Applications/Qoder.app", directoryHint: .isDirectory),
        ]
        return QoderEnvironment(
            home: home,
            homeExists: fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory) && isDirectory.boolValue,
            application: applications.first { fileManager.fileExists(atPath: $0.path) },
            executable: ExecutableLocator.newest(
                among: ExecutableLocator.commonCandidates(named: "qodercli", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            )
        )
    }
}
