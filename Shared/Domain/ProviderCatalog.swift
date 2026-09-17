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
    case kiro
    case warp
    case deepseek
    case kimi
    case openrouter
    case cursor
    case copilot
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
    /// Set for providers read with the person's own API key: the only host
    /// that key is ever sent to, and where to create one.
    var apiKey: APIKeyConnection? = nil
}

/// How a provider connected with an API key talks to its service.
struct APIKeyConnection: Sendable, Equatable {
    /// The one host the key is sent to. Requests anywhere else are refused.
    let host: String
    /// The provider's page for creating a key.
    let keysPage: URL
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
            summary: "Track Antigravity limits while the Antigravity app runs.",
            availability: .available,
            logoAssetName: "AntigravityLogo",
            symbolName: "circle.hexagonpath"
        ),
        ProviderDefinition(
            id: .kiro,
            displayName: "Kiro",
            summary: "Track Kiro credits and monthly limits.",
            availability: .available,
            logoAssetName: "KiroLogo",
            symbolName: "sparkles"
        ),
        ProviderDefinition(
            id: .warp,
            displayName: "Warp",
            summary: "Track Warp agent requests and credits.",
            availability: .available,
            logoAssetName: "WarpLogo",
            symbolName: "terminal"
        ),
        ProviderDefinition(
            id: .deepseek,
            displayName: "DeepSeek",
            summary: "Track your DeepSeek API balance.",
            availability: .available,
            logoAssetName: "DeepSeekLogo",
            symbolName: "circle.dashed",
            apiKey: APIKeyConnection(host: "api.deepseek.com", keysPage: URL(string: "https://platform.deepseek.com/api_keys")!)
        ),
        ProviderDefinition(
            id: .kimi,
            displayName: "Kimi",
            summary: "Track your Kimi API balance.",
            availability: .available,
            logoAssetName: nil,
            symbolName: "moon",
            apiKey: APIKeyConnection(host: "api.moonshot.ai", keysPage: URL(string: "https://platform.moonshot.ai/console/api-keys")!)
        ),
        ProviderDefinition(
            id: .openrouter,
            displayName: "OpenRouter",
            summary: "Track OpenRouter spending and key limits.",
            availability: .available,
            logoAssetName: nil,
            symbolName: "arrow.triangle.branch",
            apiKey: APIKeyConnection(host: "openrouter.ai", keysPage: URL(string: "https://openrouter.ai/settings/keys")!)
        ),
        ProviderDefinition(
            id: .cursor,
            displayName: "Cursor",
            summary: nil,
            availability: .comingSoon,
            logoAssetName: "CursorLogo",
            symbolName: "cursorarrow"
        ),
        ProviderDefinition(
            id: .copilot,
            displayName: "GitHub Copilot",
            summary: nil,
            availability: .comingSoon,
            logoAssetName: "CopilotLogo",
            symbolName: "chevron.left.forwardslash.chevron.right"
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
