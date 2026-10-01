import AppKit
import Foundation

/// A plain-text report for "Report a Problem": what UsageNow sees, without
/// anything about the person.
///
/// It's shown in full before anything leaves the Mac, and it leaves only
/// when the person submits it themselves — on GitHub or by email.
///
/// In it: versions, screens, settings, and each provider's status, limits,
/// and refresh errors. Never in it: account names or emails, file paths
/// (the home folder becomes `~`), API keys, tokens, or anything from a
/// prompt or reply. Error messages are cleaned the same way before they're
/// included, since a system error can quote a path.
enum DiagnosticReport {
    @MainActor
    struct Environment {
        var appVersion = AppInfo.version
        var build = AppInfo.build
        var macOS = ProcessInfo.processInfo.operatingSystemVersionString
        var architecture = DiagnosticReport.architecture
        var screens: [String] = DiagnosticReport.screenDescriptions()
        var menuBarManagers: [String] = DiagnosticReport.runningMenuBarManagers()
        var homeDirectory = NSHomeDirectory()
    }

    struct Settings: Sendable {
        var appearance: String
        var usageAmountStyle: String
        var showsActivityHistory: Bool
        var refreshInterval: String
        var menuBarDisplayMode: String
        var fetchClaudeUsageLimits: Bool
        var notifiesAboutLimits = false
        var hasPopoverShortcut = false
    }

    @MainActor
    static func make(
        states: [ProviderState],
        order: [ProviderID],
        enabled: Set<ProviderID>,
        hasAPIKey: (ProviderID) -> Bool,
        settings: Settings,
        environment: Environment = Environment(),
        now: Date = .now
    ) -> String {
        var lines: [String] = []
        lines.append("UsageNow \(environment.appVersion) (\(environment.build))")
        lines.append("macOS \(environment.macOS), \(environment.architecture)")
        lines.append("Screens: \(environment.screens.isEmpty ? "unknown" : environment.screens.joined(separator: "; "))")
        lines.append("Menu bar managers running: \(environment.menuBarManagers.isEmpty ? "none" : environment.menuBarManagers.joined(separator: ", "))")
        lines.append(
            "Settings: appearance \(settings.appearance), limits as \(settings.usageAmountStyle), "
                + "30-day charts \(settings.showsActivityHistory ? "on" : "off"), refresh \(settings.refreshInterval), "
                + "menu bar \(settings.menuBarDisplayMode), Claude limits (experimental) \(settings.fetchClaudeUsageLimits ? "on" : "off"), "
                + "limit notifications \(settings.notifiesAboutLimits ? "on" : "off"), global shortcut \(settings.hasPopoverShortcut ? "set" : "not set")"
        )
        lines.append("")
        lines.append("Providers, in popover order:")

        for id in order where enabled.contains(id) {
            let state = states.first { $0.provider == id }
            lines.append("- \(id.displayName): \(describe(state, id: id, hasAPIKey: hasAPIKey, now: now))")
            if let failure = state?.failure {
                let clean = sanitized(failure.message, homeDirectory: environment.homeDirectory)
                lines.append("  Last refresh failed \(age(of: failure.date, now: now)): \(clean)")
            }
        }

        let off = ProviderCatalog.available.map(\.id).filter { !enabled.contains($0) }
        if !off.isEmpty {
            lines.append("Turned off: \(off.map(\.displayName).joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Providers

    private static func describe(_ state: ProviderState?, id: ProviderID, hasAPIKey: (ProviderID) -> Bool, now: Date) -> String {
        var parts: [String] = []
        if ProviderCatalog.definition(for: id).apiKey != nil {
            parts.append(hasAPIKey(id) ? "API key saved" : "no API key")
        }
        guard let snapshot = state?.snapshot else {
            parts.append(state?.isRefreshing == true ? "loading" : "no reading yet")
            return parts.joined(separator: "; ")
        }
        parts.append(String(describing: snapshot.status))
        if let plan = snapshot.planName { parts.append("plan \(plan)") }
        for window in snapshot.windows {
            var text = "\(window.kind) " + (window.usage.map { "\($0.displayValue)% used" } ?? "unknown")
            if let scope = window.scope { text += " (\(scope))" }
            if let resetsAt = window.resetsAt { text += ", resets \(age(of: resetsAt, now: now))" }
            parts.append(text)
        }
        if let reason = snapshot.quotaUnavailableReason { parts.append("limits unavailable: \(reason.rawValue)") }
        if let balance = snapshot.balance {
            parts.append("balance reported in \(balance.currency)\(balance.canMakeRequests ? "" : ", can't pay for requests")")
        }
        let activity = snapshot.activity
        if let tokens = activity.tokensToday { parts.append("\(tokens) tokens today") }
        if let requests = activity.requestsToday { parts.append("\(requests) requests today") }
        if let credits = activity.creditsToday {
            let amount = UsageFormatter.credits(credits, locale: Locale(identifier: "en_US_POSIX"))
            parts.append("\(amount) credits today\(activity.isCreditsComplete ? "" : " (partial)")")
        }
        if let history = activity.history {
            parts.append("active on \(history.days.filter { history.value(of: $0) > 0 }.count) of \(history.days.count) days")
        }
        parts.append("updated \(age(of: snapshot.updatedAt, now: now))")
        if let limits = snapshot.limitsUpdatedAt { parts.append("limits from \(age(of: limits, now: now))") }
        return parts.joined(separator: "; ")
    }

    /// "5m ago", "in 2h" — relative, so the report doesn't carry the clock time.
    static func age(of date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        let magnitude = abs(seconds)
        if magnitude < 5 { return "just now" }
        let text = switch magnitude {
        case ..<60: "\(magnitude)s"
        case ..<3600: "\(magnitude / 60)m"
        case ..<86_400: "\(magnitude / 3600)h"
        default: "\(magnitude / 86_400)d"
        }
        return seconds < 0 ? "\(text) ago" : "in \(text)"
    }

    // MARK: Cleaning

    /// Removes what could identify the person from a message: the home
    /// folder, other users' folders, email addresses, and anything shaped
    /// like a key or token.
    static func sanitized(_ message: String, homeDirectory: String) -> String {
        var text = message
        if !homeDirectory.isEmpty {
            text = text.replacingOccurrences(of: homeDirectory, with: "~")
        }
        let patterns: [(String, String)] = [
            (#"/Users/[^/\s]+"#, "/Users/…"),
            (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "<email>"),
            (#"[A-Za-z0-9_\-]{24,}"#, "<redacted>"),
        ]
        for (pattern, replacement) in patterns {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return text
    }

    // MARK: This Mac

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    /// Size, scale, and whether the screen has a camera housing, which
    /// crowds the menu bar. The popover's size depends on all three.
    @MainActor
    static func screenDescriptions() -> [String] {
        NSScreen.screens.map { screen in
            let size = screen.visibleFrame.size
            let notch = screen.safeAreaInsets.top > 0 ? ", notch" : ""
            return "\(Int(size.width))×\(Int(size.height)) visible @\(Int(screen.backingScaleFactor))x\(notch)"
        }
    }

    /// Apps that rearrange menu bar items, by name only. They can move or
    /// hide UsageNow's item, which closes its window.
    @MainActor
    static func runningMenuBarManagers() -> [String] {
        let known: Set<String> = ["Bartender", "Bartender 4", "Bartender 5", "Bartender 6", "Ice", "Thaw", "Hidden Bar", "Vanilla", "Dozer", "Barbee", "Menu Bar Controller"]
        let running = NSWorkspace.shared.runningApplications.compactMap(\.localizedName).filter(known.contains)
        return Array(Set(running)).sorted()
    }
}
