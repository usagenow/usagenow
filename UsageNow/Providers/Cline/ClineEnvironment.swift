import Foundation

/// Where Cline keeps what UsageNow reads.
///
/// - The editor extension saves each task under its editor's storage:
///   `…/User/globalStorage/saoudrizwan.claude-dev/tasks/<task>/ui_messages.json`,
///   for VS Code, Cursor, Windsurf, Kiro, and VSCodium alike.
/// - The command-line Cline saves sessions as
///   `~/.cline/data/sessions/<session>/<session>.messages.json`.
///
/// Discovery checks that folders exist and opens nothing. Cline's keys
/// (`secrets.json`, the editor's secret storage) are never touched.
struct ClineEnvironment: Sendable, Equatable {
    static let extensionID = "saoudrizwan.claude-dev"
    /// Editors whose application support folder may hold Cline's tasks.
    static let editors = ["Code", "Code - Insiders", "Cursor", "Windsurf", "Kiro", "VSCodium", "Trae"]

    /// `tasks` folders of the editor extension that exist on this Mac.
    var extensionTaskRoots: [URL]
    /// `~/.cline/data`, when the command-line Cline has run here.
    var cliData: URL?
    var executable: URL?

    var isInstalled: Bool { !extensionTaskRoots.isEmpty || cliData != nil || executable != nil }

    /// Folders holding one folder per CLI session; tasks the CLI writes in
    /// the extension's format live beside them.
    var cliSessionsRoot: URL? { cliData?.appending(path: "sessions", directoryHint: .isDirectory) }
    var cliTasksRoot: URL? { cliData?.appending(path: "tasks", directoryHint: .isDirectory) }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> ClineEnvironment {
        let support = homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let roots = editors
            .map { support.appending(path: "\($0)/User/globalStorage/\(extensionID)/tasks", directoryHint: .isDirectory) }
            .filter { isDirectory($0, fileManager: fileManager) }
        let cliData = homeDirectory.appending(path: ".cline/data", directoryHint: .isDirectory)
        return ClineEnvironment(
            extensionTaskRoots: roots,
            cliData: isDirectory(cliData, fileManager: fileManager) ? cliData : nil,
            executable: ExecutableLocator.newest(
                among: ExecutableLocator.commonCandidates(named: "cline", homeDirectory: homeDirectory, fileManager: fileManager),
                fileManager: fileManager
            )
        )
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
