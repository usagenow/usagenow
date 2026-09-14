import Foundation

/// Identifies a tool UsageNow can track, including ones still on the roadmap.
///
/// These raw values are persisted, so they must stay stable. Display names
/// live in `ProviderCatalog` and are never used as identifiers.
/// Case order is display order.
enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case codex
    case claudeCode
    case gemini
    case antigravity
    case deepseek
    case qwen

    var id: String { rawValue }

    /// Product name. Never localized.
    var displayName: String { ProviderCatalog.definition(for: self).displayName }

    var isAvailable: Bool { ProviderCatalog.definition(for: self).availability == .available }

    static func < (lhs: ProviderID, rhs: ProviderID) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

enum ProviderAvailability: Sendable, Equatable {
    /// Implemented and can be turned on.
    case available
    /// A roadmap entry. No integration, no credentials, no network or file access.
    case comingSoon
}

/// Everything the UI needs to know about a provider, in one place.
struct ProviderDefinition: Sendable, Identifiable, Equatable {
    let id: ProviderID
    /// Never localized.
    let displayName: String
    /// Shown under the name for available providers.
    let summary: LocalizedStringResource?
    let availability: ProviderAvailability
    /// Official artwork, when UsageNow already ships it.
    let logoAssetName: String?
    /// Neutral placeholder used when there's no official artwork.
    let symbolName: String
}

/// The single source of truth for provider metadata.
///
/// Roadmap entries exist here so the UI can list them; they have no
/// integration behind them.
enum ProviderCatalog {
    static let all: [ProviderDefinition] = [
        ProviderDefinition(
            id: .codex,
            displayName: "Codex",
            summary: "Track Codex usage and limits.",
            availability: .available,
            logoAssetName: "OpenAILogo",
            symbolName: "terminal"
        ),
        ProviderDefinition(
            id: .claudeCode,
            displayName: "Claude Code",
            summary: "Track Claude Code usage and limits.",
            availability: .available,
            logoAssetName: "ClaudeLogo",
            symbolName: "asterisk"
        ),
        ProviderDefinition(
            id: .gemini,
            displayName: "Gemini CLI",
            summary: "Track Gemini CLI activity by model.",
            availability: .available,
            logoAssetName: "GeminiLogo",
            symbolName: "sparkle"
        ),
        ProviderDefinition(
            id: .antigravity,
            displayName: "Antigravity",
            summary: nil,
            availability: .comingSoon,
            logoAssetName: "AntigravityLogo",
            symbolName: "circle.hexagonpath"
        ),
        ProviderDefinition(
            id: .deepseek,
            displayName: "DeepSeek",
            summary: nil,
            availability: .comingSoon,
            logoAssetName: "DeepSeekLogo",
            symbolName: "circle.dashed"
        ),
        ProviderDefinition(
            id: .qwen,
            displayName: "Qwen",
            summary: nil,
            availability: .comingSoon,
            logoAssetName: "QwenLogo",
            symbolName: "circle.dashed"
        ),
    ]

    static func definition(for id: ProviderID) -> ProviderDefinition {
        // Every case is listed above; the fallback keeps this total.
        all.first { $0.id == id }
            ?? ProviderDefinition(id: id, displayName: id.rawValue, summary: nil, availability: .comingSoon, logoAssetName: nil, symbolName: "circle.dashed")
    }

    static var available: [ProviderDefinition] {
        all.filter { $0.availability == .available }
    }

    static var comingSoon: [ProviderDefinition] {
        all.filter { $0.availability == .comingSoon }
    }

    static var availableIDs: Set<ProviderID> {
        Set(available.map(\.id))
    }
}
