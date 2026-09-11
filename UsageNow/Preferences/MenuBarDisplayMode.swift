import Foundation

/// What the menu bar item shows next to (or instead of) the icon.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    /// The usage window closest to exhaustion across providers.
    case mostCriticalPercentage
    case codexPercentage
    case claudePercentage

    static let `default` = MenuBarDisplayMode.iconOnly

    /// Modes offered in Settings.
    static let available: [MenuBarDisplayMode] = allCases

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .iconOnly: "Icon only"
        case .mostCriticalPercentage: "Most critical usage"
        case .codexPercentage: "Codex usage"
        case .claudePercentage: "Claude Code usage"
        }
    }

    /// The percentage to show in the menu bar, or `nil` to show only the icon.
    ///
    /// Falls back to the icon when no quota is available — for example the
    /// selected provider is signed out or reports no limits — instead of
    /// showing 0%. Only one percentage is ever shown.
    func usage(in snapshots: [ProviderSnapshot]) -> UsagePercentage? {
        switch self {
        case .iconOnly:
            nil
        case .mostCriticalPercentage:
            UsageSummary.mostCritical(in: snapshots)?.window.usage
        case .codexPercentage:
            UsageSummary.mostCritical(in: snapshots.filter { $0.provider == .codex })?.window.usage
        case .claudePercentage:
            UsageSummary.mostCritical(in: snapshots.filter { $0.provider == .claudeCode })?.window.usage
        }
    }
}
