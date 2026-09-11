import Foundation

/// Identifies a tool whose usage UsageNow tracks.
///
/// Case order defines display order throughout the app.
enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case codex
    case claudeCode

    var id: String { rawValue }

    /// Product name. Not localized.
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    static func < (lhs: ProviderID, rhs: ProviderID) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
