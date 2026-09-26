import Foundation
import Observation

/// Simple user preferences, persisted in `UserDefaults`.
///
/// Observable so services (like auto-refresh) can react to changes,
/// not just views.
@Observable
@MainActor
final class AppPreferences {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let appearance = "appearance"
        static let usageAmountStyle = "usageAmountStyle"
        static let showsActivityHistory = "showsActivityHistory"
        static let fetchClaudeUsageLimits = "experimental.fetchClaudeUsageLimits"
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Whether limits read as what's left or what's used, everywhere.
    var usageAmountStyle: UsageAmountStyle {
        didSet { defaults.set(usageAmountStyle.rawValue, forKey: Key.usageAmountStyle) }
    }

    /// The 30-day chart under each provider in the popover. On by default;
    /// off keeps the popover compact with many providers.
    var showsActivityHistory: Bool {
        didSet { defaults.set(showsActivityHistory, forKey: Key.showsActivityHistory) }
    }

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode) }
    }

    /// Experimental: read Claude Code subscription limits from Anthropic's
    /// undocumented usage endpoint. Off by default.
    var fetchClaudeUsageLimits: Bool {
        didSet { defaults.set(fetchClaudeUsageLimits, forKey: Key.fetchClaudeUsageLimits) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .default
        usageAmountStyle = defaults.string(forKey: Key.usageAmountStyle).flatMap(UsageAmountStyle.init(rawValue:)) ?? .default
        showsActivityHistory = defaults.object(forKey: Key.showsActivityHistory) as? Bool ?? true
        fetchClaudeUsageLimits = defaults.bool(forKey: Key.fetchClaudeUsageLimits)
        refreshInterval = (defaults.object(forKey: Key.refreshInterval) as? Int)
            .flatMap(RefreshInterval.init(rawValue:)) ?? .default
        // Unknown identifiers fall back to the default.
        menuBarDisplayMode = defaults.string(forKey: Key.menuBarDisplayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .default
    }
}
