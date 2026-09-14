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
        static let fetchClaudeUsageLimits = "experimental.fetchClaudeUsageLimits"
        static let fetchAntigravityUsageLimits = "experimental.fetchAntigravityUsageLimits"
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
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

    /// Experimental: read Antigravity limits from Google's undocumented
    /// Cloud Code quota endpoint. Off by default.
    var fetchAntigravityUsageLimits: Bool {
        didSet { defaults.set(fetchAntigravityUsageLimits, forKey: Key.fetchAntigravityUsageLimits) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .default
        fetchClaudeUsageLimits = defaults.bool(forKey: Key.fetchClaudeUsageLimits)
        fetchAntigravityUsageLimits = defaults.bool(forKey: Key.fetchAntigravityUsageLimits)
        refreshInterval = (defaults.object(forKey: Key.refreshInterval) as? Int)
            .flatMap(RefreshInterval.init(rawValue:)) ?? .default
        // Unknown identifiers fall back to the default.
        menuBarDisplayMode = defaults.string(forKey: Key.menuBarDisplayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .default
    }
}
