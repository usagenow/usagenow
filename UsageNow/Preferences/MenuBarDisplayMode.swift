import Foundation

/// What the menu bar item shows next to (or instead of) the icon.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    /// The usage window closest to exhaustion across providers.
    case mostCriticalPercentage
    case codexPercentage
    case claudePercentage
    /// Gemini CLI reports no limits today, so this shows the icon until it does.
    case geminiPercentage
    case antigravityPercentage
    case kiroPercentage
    case windsurfPercentage
    case cursorPercentage
    case copilotPercentage
    case perplexityPercentage
    case elevenLabsPercentage
    case zaiPercentage

    static let `default` = MenuBarDisplayMode.iconOnly

    /// The provider a mode needs; `nil` when it works with any.
    var requiredProvider: ProviderID? {
        switch self {
        case .iconOnly, .mostCriticalPercentage: nil
        case .codexPercentage: .codex
        case .claudePercentage: .claudeCode
        case .geminiPercentage: .gemini
        case .antigravityPercentage: .antigravity
        case .kiroPercentage: .kiro
        case .windsurfPercentage: .windsurf
        case .cursorPercentage: .cursor
        case .copilotPercentage: .copilot
        case .perplexityPercentage: .perplexity
        case .elevenLabsPercentage: .elevenlabs
        case .zaiPercentage: .zai
        }
    }

    /// Modes offered in Settings. A provider-specific mode disappears when
    /// that provider is turned off.
    static func available(for enabledProviders: Set<ProviderID>) -> [MenuBarDisplayMode] {
        allCases.filter { mode in
            mode.requiredProvider.map(enabledProviders.contains) ?? true
        }
    }

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .iconOnly: "Icon only"
        case .mostCriticalPercentage: "Most critical usage"
        case .codexPercentage: "Codex usage"
        case .claudePercentage: "Claude Code usage"
        case .geminiPercentage: "Gemini CLI usage"
        case .antigravityPercentage: "Antigravity usage"
        case .kiroPercentage: "Kiro usage"
        case .windsurfPercentage: "Windsurf usage"
        case .cursorPercentage: "Cursor usage"
        case .copilotPercentage: "GitHub Copilot usage"
        case .perplexityPercentage: "Perplexity usage"
        case .elevenLabsPercentage: "ElevenLabs usage"
        case .zaiPercentage: "Z.ai usage"
        }
    }

    /// The percentage to show in the menu bar, or `nil` to show only the icon.
    ///
    /// Falls back to the icon when no quota is available — for example the
    /// selected provider is signed out or reports no limits — instead of
    /// showing 0%. Only one percentage is ever shown.
    ///
    /// - Parameter account: For a provider's mode, the added account to
    ///   show; `nil` for the provider's own.
    func usage(in snapshots: [ProviderSnapshot], account: String? = nil) -> UsagePercentage? {
        switch self {
        case .iconOnly:
            nil
        case .mostCriticalPercentage:
            UsageSummary.mostCritical(in: snapshots)?.window.usage
        default:
            UsageSummary.mostCritical(in: snapshots.filter { $0.provider == requiredProvider && $0.account?.id == account })?.window.usage
        }
    }
}

/// One entry of the menu bar's Display picker: a mode, and for a
/// provider's mode, which of its accounts.
struct MenuBarChoice: Hashable, Identifiable, Sendable {
    var mode: MenuBarDisplayMode
    /// An added account's identifier; `nil` for the provider's own account.
    var account: String? = nil

    static let `default` = MenuBarChoice(mode: .default)

    var id: String { account.map { "\(mode.rawValue)@\($0)" } ?? mode.rawValue }

    /// Every mode available, each provider's mode followed by one entry per
    /// account added to that provider.
    static func available(for enabledProviders: Set<ProviderID>, accounts: [ProviderAccount]) -> [MenuBarChoice] {
        MenuBarDisplayMode.available(for: enabledProviders).flatMap { mode in
            let added = mode.requiredProvider.map { provider in accounts.filter { $0.provider == provider } } ?? []
            return [MenuBarChoice(mode: mode)] + added.map { MenuBarChoice(mode: mode, account: $0.id) }
        }
    }

    /// "Codex usage", or "Codex · Work usage" for an added account.
    func title(accounts: [ProviderAccount]) -> String {
        guard let provider = mode.requiredProvider,
              let added = accounts.first(where: { $0.id == account && $0.provider == provider }) else {
            return String(localized: mode.title)
        }
        return String(localized: "\(provider.displayName(account: added.tag)) usage")
    }

    /// This choice if its account still exists and belongs to the mode's
    /// provider; otherwise the provider's own account.
    func validated(against accounts: [ProviderAccount]) -> MenuBarChoice {
        guard let account else { return self }
        let exists = accounts.contains { $0.id == account && $0.provider == mode.requiredProvider }
        return exists ? self : MenuBarChoice(mode: mode)
    }
}
