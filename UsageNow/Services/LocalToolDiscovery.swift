import Foundation

/// First-run hints inspect existence only: no file contents or credentials.
enum LocalToolDiscovery {
    static func installed(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<ProviderID> {
        let folders: [ProviderID: [String]] = [
            .codex: [".codex"], .claudeCode: [".claude"], .gemini: [".gemini"],
            .antigravity: [".gemini/antigravity", ".gemini/antigravity-cli"],
            .kiro: [".kiro"], .warp: ["Library/Application Support/dev.warp.Warp-Stable"],
            .opencode: [".local/share/opencode"], .qoder: [".qoder"], .qwen: [".qwen"],
            .cline: [".cline"], .grok: [".grok"],
            .windsurf: ["Library/Application Support/Windsurf"],
            .jetbrains: ["Library/Application Support/JetBrains"],
        ]
        let apps: [ProviderID: String] = [.codex: "Codex", .antigravity: "Antigravity", .kiro: "Kiro", .warp: "Warp", .opencode: "OpenCode", .qoder: "Qoder", .windsurf: "Windsurf"]
        return Set(folders.compactMap { provider, paths in
            let local = paths.contains { FileManager.default.fileExists(atPath: home.appending(path: $0).path) }
            let app = apps[provider].map { FileManager.default.fileExists(atPath: "/Applications/\($0).app") } ?? false
            return local || app ? provider : nil
        })
    }
}
