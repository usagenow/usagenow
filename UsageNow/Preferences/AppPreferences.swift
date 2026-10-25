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
        static let menuBarAccount = "menuBarAccount"
        static let appearance = "appearance"
        static let usageAmountStyle = "usageAmountStyle"
        static let showsActivityHistory = "showsActivityHistory"
        static let showsServiceStatus = "showsServiceStatus"
        static let fetchClaudeUsageLimits = "experimental.fetchClaudeUsageLimits"
        static let notifiesAboutLimits = "notifiesAboutLimits"
        static let notificationPolicy = "notificationPolicy.v1"
        static let popoverShortcut = "popoverShortcut"
        /// macOS's own per-app language list, the one System Settings writes.
        static let appleLanguages = "AppleLanguages"
    }

    /// The language UsageNow uses from its next launch. Stored where macOS
    /// keeps a per-app language, so System Settings and this choice agree.
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            if let code = language.code {
                defaults.set([code], forKey: Key.appleLanguages)
            } else {
                defaults.removeObject(forKey: Key.appleLanguages)
            }
        }
    }

    /// The language this launch is running in; differs from `language`
    /// until UsageNow restarts.
    @ObservationIgnored let languageAtLaunch: AppLanguage

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

    /// Optional public status checks, independent of account usage.
    var showsServiceStatus: Bool {
        didSet { defaults.set(showsServiceStatus, forKey: Key.showsServiceStatus) }
    }

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode) }
    }

    /// For a provider's mode, the added account the menu bar shows; `nil`
    /// for the provider's own account.
    var menuBarAccount: String? {
        didSet { defaults.set(menuBarAccount, forKey: Key.menuBarAccount) }
    }

    /// The mode and account together, as the Display picker sets them.
    var menuBarChoice: MenuBarChoice {
        get { MenuBarChoice(mode: menuBarDisplayMode, account: menuBarAccount) }
        set {
            menuBarDisplayMode = newValue.mode
            menuBarAccount = newValue.account
        }
    }

    /// Experimental: read Claude Code subscription limits from Anthropic's
    /// undocumented usage endpoint. Off by default.
    var fetchClaudeUsageLimits: Bool {
        didSet { defaults.set(fetchClaudeUsageLimits, forKey: Key.fetchClaudeUsageLimits) }
    }

    /// Notifications when a limit runs low and when it resets. Off by default.
    var notifiesAboutLimits: Bool {
        didSet { defaults.set(notifiesAboutLimits, forKey: Key.notifiesAboutLimits) }
    }

    var notificationPolicy: NotificationPolicy {
        didSet { defaults.set(try? JSONEncoder().encode(notificationPolicy), forKey: Key.notificationPolicy) }
    }

    /// Opens the menu bar window from any app. None until the person records one.
    var popoverShortcut: GlobalShortcut? {
        didSet { defaults.set(popoverShortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.popoverShortcut) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter languageDomain: The defaults domain holding the per-app
    ///   language: UsageNow's own, or a test suite's name. Reading the key
    ///   through `defaults` would also find the system-wide list.
    init(defaults: UserDefaults = .standard, languageDomain: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        let stored = languageDomain.flatMap { defaults.persistentDomain(forName: $0)?[Key.appleLanguages] as? [String] }
        language = AppLanguage(preferredLanguages: stored)
        languageAtLaunch = AppLanguage(preferredLanguages: stored)
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .default
        usageAmountStyle = defaults.string(forKey: Key.usageAmountStyle).flatMap(UsageAmountStyle.init(rawValue:)) ?? .default
        showsActivityHistory = defaults.object(forKey: Key.showsActivityHistory) as? Bool ?? true
        showsServiceStatus = defaults.bool(forKey: Key.showsServiceStatus)
        fetchClaudeUsageLimits = defaults.bool(forKey: Key.fetchClaudeUsageLimits)
        notifiesAboutLimits = defaults.bool(forKey: Key.notifiesAboutLimits)
        notificationPolicy = defaults.data(forKey: Key.notificationPolicy)
            .flatMap { try? JSONDecoder().decode(NotificationPolicy.self, from: $0) } ?? NotificationPolicy()
        popoverShortcut = defaults.data(forKey: Key.popoverShortcut).flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }
        refreshInterval = (defaults.object(forKey: Key.refreshInterval) as? Int)
            .flatMap(RefreshInterval.init(rawValue:)) ?? .default
        // Unknown identifiers fall back to the default.
        menuBarDisplayMode = defaults.string(forKey: Key.menuBarDisplayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .default
        menuBarAccount = defaults.string(forKey: Key.menuBarAccount)
    }
}
