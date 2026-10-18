import Foundation

/// Discovery inspects names and file metadata, never IDE accounts, settings
/// other than the quota file, prompt libraries, or authentication stores.
struct JetBrainsEnvironment: Sendable {
    struct Installation: Sendable {
        let name: String
        let quotaFile: URL
        let logFile: URL
        let quotaModifiedAt: Date?
        let logModifiedAt: Date?
        let hasQuotaFile: Bool
    }

    let installations: [Installation]

    /// An XML cache chooses the installation, even if its contents are
    /// unknown. Another IDE may use a completely different account.
    var selected: Installation? {
        let withQuota = installations.filter(\.hasQuotaFile)
        let candidates = withQuota.isEmpty ? installations : withQuota
        return candidates.sorted {
            let lhs = withQuota.isEmpty ? $0.logModifiedAt : $0.quotaModifiedAt
            let rhs = withQuota.isEmpty ? $1.logModifiedAt : $1.quotaModifiedAt
            if lhs != rhs { return (lhs ?? .distantPast) > (rhs ?? .distantPast) }
            return $0.name < $1.name
        }.first
    }

    static func discover(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let manager = FileManager.default
        var installations: [String: Installation] = [:]
        for vendor in ["JetBrains", "Google"] {
            let configRoot = homeDirectory.appending(path: "Library/Application Support/\(vendor)")
            let logsRoot = homeDirectory.appending(path: "Library/Logs/\(vendor)")
            // Logs-only installations can still report current quota.
            for root in [configRoot, logsRoot] {
                guard isPlainDirectory(root) else { continue }
                let children = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(128) {
                    let folder = child.lastPathComponent
                    guard let name = displayName(folder: folder, vendor: vendor), isPlainDirectory(child) else { continue }
                    let options = configRoot.appending(path: folder).appending(path: "options")
                    let quota = options.appending(path: "AIAssistantQuotaManager2.xml")
                    let logDirectory = logsRoot.appending(path: folder)
                    let log = logDirectory.appending(path: "idea.log")
                    let quotaInfo = isPlainDirectory(configRoot) && isPlainDirectory(options.deletingLastPathComponent()) && isPlainDirectory(options)
                        ? JetBrainsQuotaReader.metadata(quota) : nil
                    let logInfo = isPlainDirectory(logsRoot) && isPlainDirectory(logDirectory)
                        ? JetBrainsQuotaReader.metadata(log) : nil
                    installations["\(vendor)/\(folder)"] = Installation(
                        name: name, quotaFile: quota, logFile: log,
                        quotaModifiedAt: quotaInfo?.modifiedAt, logModifiedAt: logInfo?.modifiedAt,
                        hasQuotaFile: quotaInfo != nil
                    )
                }
            }
        }
        return Self(installations: Array(installations.values))
    }

    private static func isPlainDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    static func displayName(folder: String, vendor: String) -> String? {
        let products = vendor == "Google" ? ["AndroidStudio": "Android Studio"] : [
            "IntelliJIdea": "IntelliJ IDEA", "IdeaIC": "IntelliJ IDEA Community",
            "PyCharm": "PyCharm", "PyCharmCE": "PyCharm Community", "WebStorm": "WebStorm",
            "GoLand": "GoLand", "CLion": "CLion", "DataGrip": "DataGrip", "RubyMine": "RubyMine",
            "Rider": "Rider", "PhpStorm": "PhpStorm", "RustRover": "RustRover", "Aqua": "Aqua",
            "DataSpell": "DataSpell", "Fleet": "Fleet",
        ]
        for (prefix, name) in products.sorted(by: { $0.key.count > $1.key.count }) where folder.hasPrefix(prefix) {
            let version = String(folder.dropFirst(prefix.count))
            guard version.range(of: #"^\d{4}\.\d+(?:\.\d+)?(?:[A-Za-z0-9._-]{0,24})$"#, options: .regularExpression) != nil else { continue }
            return "\(name) \(version)"
        }
        return nil
    }
}
