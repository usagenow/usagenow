import Foundation

/// Explicit opt-in link installation. Never replaces another command.
struct CLIInstallation {
    let helper: URL
    let link: URL

    var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == helper.path
    }

    func install() throws {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Fails for existing files and dangling links. No overwrite operation.
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)
    }

    func remove() throws {
        guard isInstalled else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: link)
    }
}
