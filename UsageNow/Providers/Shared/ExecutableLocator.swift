import Foundation

/// Finds a command-line tool in its usual install locations.
///
/// Apps launched from Finder don't inherit the shell's `PATH`, so it isn't
/// searched. A Mac often has more than one copy — a native install left
/// behind after switching to npm, or one per Node version — so the most
/// recently installed binary wins rather than the first one found.
enum ExecutableLocator {
    /// Locations shared by most CLIs: `~/.local/bin`, Homebrew, `/usr/local`,
    /// Bun, and every Node version under nvm.
    static func commonCandidates(named name: String, homeDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        var candidates = [
            homeDirectory.appending(path: ".local/bin/\(name)"),
            URL(filePath: "/opt/homebrew/bin/\(name)"),
            URL(filePath: "/usr/local/bin/\(name)"),
            homeDirectory.appending(path: ".bun/bin/\(name)"),
        ]
        let nodeVersions = homeDirectory.appending(path: ".nvm/versions/node")
        if let nodes = try? fileManager.contentsOfDirectory(atPath: nodeVersions.path) {
            candidates += nodes.sorted(by: >).map { nodeVersions.appending(path: "\($0)/bin/\(name)") }
        }
        return candidates
    }

    /// The executable among `candidates` whose binary was written most recently.
    static func newest(among candidates: [URL], fileManager: FileManager = .default) -> URL? {
        candidates
            .filter { fileManager.isExecutableFile(atPath: $0.path) }
            .max { installDate(of: $0, fileManager) < installDate(of: $1, fileManager) }
    }

    /// When the binary a candidate points at was written; symlinks are followed.
    private static func installDate(of executable: URL, _ fileManager: FileManager) -> Date {
        let target = executable.resolvingSymlinksInPath()
        return (try? fileManager.attributesOfItem(atPath: target.path)[.modificationDate] as? Date) ?? .distantPast
    }
}
