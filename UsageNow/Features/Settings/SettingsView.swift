import AppKit
import SwiftUI

enum SettingsTab: Hashable, Sendable, CaseIterable {
    case general
    case providers
    case menuBar
    case notifications
    case privacy
    case about

    /// The tab's title in the toolbar, as the language UsageNow runs in has it.
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .providers: String(localized: "Providers")
        case .menuBar: String(localized: "Menu Bar")
        case .notifications: String(localized: "Notifications")
        case .privacy: String(localized: "Privacy")
        case .about: String(localized: "About")
        }
    }
}

struct SettingsView: View {
    /// Wide enough for every tab's title in the toolbar. When they don't
    /// fit, macOS moves the last tabs into an overflow menu, where Settings
    /// tabs can't be chosen — Russian, French, and Spanish titles are longer
    /// than 480 points allow.
    static let width: CGFloat = toolbarWidth(for: SettingsTab.allCases.map(\.title))

    /// The narrowest width that fits these toolbar titles, and never less
    /// than 480.
    static func toolbarWidth(for titles: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        // Each toolbar item pads its title and is never narrower than its
        // icon; the window keeps a margin on each side for the items.
        let items = titles.map { max(($0 as NSString).size(withAttributes: [.font: font]).width + 16, 52) }
        return max(480, (items.reduce(0, +) + 80).rounded(.up))
    }

    let preferences: AppPreferences
    let providerPreferences: ProviderPreferences
    let analyticsPreferences: AnalyticsPreferences
    let launchAtLogin: LaunchAtLogin
    let updates: UpdateController
    let store: UsageStore
    let limitNotifier: LimitNotifier
    var hotKey: GlobalHotKey = .shared
    /// Asks an experimental limits source to try again, keychain included.
    let retryLimits: (ProviderID) -> Void
    /// Whether a provider's first account (`nil`) or an added one has a key.
    var hasAPIKey: (ProviderID, String?) -> Bool = { _, _ in false }
    var setAPIKey: (String?, ProviderID, String?) throws -> Void = { _, _, _ in }
    var removeAccount: (ProviderAccount) -> Void = { _ in }
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView(
                    preferences: preferences,
                    providerPreferences: providerPreferences,
                    launchAtLogin: launchAtLogin,
                    updates: updates,
                    store: store,
                    retryLimits: retryLimits
                )
            }
            Tab("Providers", systemImage: "circle.hexagongrid", value: SettingsTab.providers) {
                ProvidersSettingsView(
                    preferences: providerPreferences,
                    hasAPIKey: hasAPIKey,
                    setAPIKey: setAPIKey,
                    removeAccount: removeAccount
                )
            }
            Tab("Menu Bar", systemImage: "menubar.rectangle", value: SettingsTab.menuBar) {
                MenuBarSettingsView(preferences: preferences, providerPreferences: providerPreferences, hotKey: hotKey)
            }
            Tab("Notifications", systemImage: "bell", value: SettingsTab.notifications) {
                NotificationsSettingsView(preferences: preferences, notifier: limitNotifier)
            }
            Tab("Privacy", systemImage: "hand.raised", value: SettingsTab.privacy) {
                PrivacySettingsView(analyticsPreferences: analyticsPreferences)
            }
            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutSettingsView(makeReport: makeReport)
            }
        }
        .frame(width: Self.width)
    }

    private func makeReport() -> String {
        DiagnosticReport.make(
            states: store.states,
            order: providerPreferences.order,
            enabled: providerPreferences.enabledProviders,
            hasAPIKey: { hasAPIKey($0, nil) },
            settings: DiagnosticReport.Settings(
                appearance: preferences.appearance.rawValue,
                usageAmountStyle: preferences.usageAmountStyle.rawValue,
                showsActivityHistory: preferences.showsActivityHistory,
                refreshInterval: "\(preferences.refreshInterval.rawValue)s",
                // Whether an added account is shown, never which.
                menuBarDisplayMode: preferences.menuBarDisplayMode.rawValue
                    + (preferences.menuBarAccount != nil ? " (added account)" : ""),
                fetchClaudeUsageLimits: preferences.fetchClaudeUsageLimits,
                notifiesAboutLimits: preferences.notifiesAboutLimits,
                hasPopoverShortcut: preferences.popoverShortcut != nil,
                language: preferences.language.rawValue
            )
        )
    }
}

struct GeneralSettingsView: View {
    @Bindable var preferences: AppPreferences
    let providerPreferences: ProviderPreferences
    let launchAtLogin: LaunchAtLogin
    @Bindable var updates: UpdateController
    let store: UsageStore
    let retryLimits: (ProviderID) -> Void

    /// Why a provider's quota is missing right now, if it is.
    private func quotaIssue(_ provider: ProviderID) -> QuotaUnavailableReason? {
        store.states.first { $0.provider == provider && $0.account == nil }?.snapshot?.quotaUnavailableReason
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch UsageNow at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { launchAtLogin.openSystemSettings() }
                    } label: {
                        Text("Allow UsageNow in System Settings to finish setup.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.checksAutomatically },
                    set: { updates.checksAutomatically = $0 }
                ))
                .disabled(!updates.isSupported)
                LabeledContent {
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                } label: {
                    Text(updates.lastCheckedDescription)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if !updates.isSupported {
                    Text("This build can't update itself: it wasn't made by the release process, which is what signs an update.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("UsageNow installs an update only when it's signed with the UsageNow update key. Checking sends no information about you.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Language", selection: $preferences.language) {
                    Text("System").tag(AppLanguage.system)
                    Divider()
                    ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                        Text(verbatim: language.nativeName ?? language.rawValue).tag(language)
                    }
                }
                if preferences.language != preferences.languageAtLaunch {
                    HStack {
                        Text("UsageNow switches language when it restarts.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Restart Now") { AppRelauncher.relaunch() }
                            .controlSize(.small)
                    }
                }
            }

            Section {
                Picker("Show limits as", selection: $preferences.usageAmountStyle) {
                    ForEach(UsageAmountStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Applies to the popover, the menu bar, and the widget.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $preferences.showsActivityHistory) {
                    Text("Show the last 30 days")
                    Text("A chart of daily activity under each provider in the menu bar window. Turn it off to keep the window short.")
                }
            }

            Section {
                Picker("Refresh interval", selection: $preferences.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
            } footer: {
                Text("UsageNow also checks for new usage when you open it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Only meaningful while Claude Code is tracked at all.
            if providerPreferences.isEnabled(.claudeCode) {
                Section {
                    Toggle(isOn: $preferences.fetchClaudeUsageLimits) {
                    Text("Fetch Claude usage limits")
                        Text("Fetch current Claude Code subscription limits directly from Anthropic using your existing Claude Code sign-in. This uses an undocumented Anthropic endpoint and may stop working without notice.")
                    }
                    if preferences.fetchClaudeUsageLimits, let issue = quotaIssue(.claudeCode) {
                        retryRow(issue, provider: .claudeCode)
                    }
                } header: {
                    Text("Claude usage limits — Experimental")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin.refreshStatus() }
    }

    private func retryRow(_ issue: QuotaUnavailableReason, provider: ProviderID) -> some View {
        LabeledContent {
            Button("Try Again") { retryLimits(provider) }
        } label: {
            Text(issue.message(for: provider))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MenuBarSettingsView: View {
    @Bindable var preferences: AppPreferences
    let providerPreferences: ProviderPreferences
    var hotKey: GlobalHotKey = .shared

    var body: some View {
        Form {
            Section {
                Picker("Display", selection: $preferences.menuBarChoice) {
                    let accounts = providerPreferences.accounts
                    ForEach(MenuBarChoice.available(for: providerPreferences.enabledProviders, accounts: accounts)) { choice in
                        Text(verbatim: choice.title(accounts: accounts)).tag(choice)
                    }
                }
            } footer: {
                Text("Shows the icon alone when no usage limit is available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorder(shortcut: $preferences.popoverShortcut)
                }
            } footer: {
                // Shown only once a shortcut is set and macOS turned it down.
                if preferences.popoverShortcut != nil, !hotKey.isRegistered {
                    Text("Another app already uses this shortcut. Record a different one.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    Text("Opens and closes UsageNow from any app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct NotificationsSettingsView: View {
    @Bindable var preferences: AppPreferences
    let notifier: LimitNotifier

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.notifiesAboutLimits) {
                    Text("Notify me about limits")
                    Text("When 20% and 5% of a limit are left, and when a limit you were warned about resets.")
                }
                if preferences.notifiesAboutLimits, notifier.permission == .denied {
                    LabeledContent {
                        Button("Open Notification Settings…") { notifier.openSystemSettings() }
                    } label: {
                        Text("Notifications are turned off for UsageNow in System Settings.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } footer: {
                Text("Limits are checked when UsageNow refreshes. Notifications come from this Mac; nothing is sent anywhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .task { await notifier.refreshPermission() }
    }
}

struct PrivacySettingsView: View {
    @Bindable var analyticsPreferences: AnalyticsPreferences

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $analyticsPreferences.isSharingEnabled) {
                    Text("Share anonymous usage analytics")
                    Text("Helps improve UsageNow by sharing basic app usage and device information.")
                }
            } header: {
                Text("Usage Analytics")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Never includes prompts, tokens, project names, files, credentials, or coding activity.")
                    if TelemetryConfiguration.current().endpoint == nil {
                        Text("This build doesn’t send analytics yet.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                Label {
                    Text("UsageNow is local-first. Your usage data stays on this Mac.")
                } icon: {
                    Image(systemName: "lock.laptopcomputer")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A report built when the sheet opens, so it describes that moment.
struct ReportDraft: Identifiable {
    let id = UUID()
    let text: String
}

struct AboutSettingsView: View {
    var makeReport: () -> String = { "" }

    @State private var isShowingChangelog = false
    @State private var isShowingLicenses = false
    @State private var report: ReportDraft?

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(verbatim: AppInfo.name)
                    .font(.title2.weight(.semibold))
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(AppInfo.summary)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Link(destination: AppInfo.website) { Text(verbatim: "usagenow.com") }
                Link(destination: AppInfo.x) { Text(verbatim: "@UsageNow") }
            }
            .font(.callout)

            HStack(spacing: 10) {
                Button("What’s New…") { isShowingChangelog = true }
                Button("Open Source Licenses…") { isShowingLicenses = true }
                Button("Report a Problem…") { report = ReportDraft(text: makeReport()) }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .sheet(isPresented: $isShowingChangelog) {
            ChangelogView()
        }
        .sheet(isPresented: $isShowingLicenses) {
            LicensesView()
        }
        .sheet(item: $report) { draft in
            ReportProblemView(report: draft.text)
        }
    }
}

extension QuotaUnavailableReason {
    /// One short sentence saying what to do. Providers keep the detailed
    /// diagnosis in their logs.
    func message(for provider: ProviderID) -> String {
        switch self {
        case .toolNotRunning where provider == .antigravity:
            String(localized: "Open the Antigravity app to update usage limits.")
        case .toolNotRunning:
            String(localized: "Open \(provider.displayName) to update usage limits.")
        case .signInExpired where provider == .claudeCode:
            String(localized: "Refresh Claude Code from Terminal to view usage limits.")
        case .permissionDenied where provider == .claudeCode:
            String(localized: "Allow UsageNow to access your Claude Code sign-in in Keychain.")
        case .temporarilyUnavailable where provider == .antigravity:
            String(localized: "Antigravity usage limits are temporarily unavailable.")
        case .temporarilyUnavailable where provider == .claudeCode:
            String(localized: "Claude usage limits are temporarily unavailable.")
        case .signInExpired:
            String(localized: "Reconnect \(provider.displayName) in Settings › Providers.")
        case .permissionDenied where provider == .elevenlabs:
            String(localized: "Allow user_read on your ElevenLabs API key, then try again.")
        case .permissionDenied:
            String(localized: "Check this connection’s permissions in Settings › Providers.")
        case .temporarilyUnavailable:
            String(localized: "\(provider.displayName) usage limits are temporarily unavailable.")
        }
    }
}

#if DEBUG
#Preview("Settings") {
    let defaults = UserDefaults(suiteName: "preview")!
    SettingsView(
        preferences: AppPreferences(defaults: defaults),
        providerPreferences: ProviderPreferences(defaults: defaults),
        analyticsPreferences: AnalyticsPreferences(defaults: defaults),
        launchAtLogin: LaunchAtLogin(),
        updates: UpdateController(),
        store: PreviewFixtures.store(codex: .normal, claude: .normal),
        limitNotifier: LimitNotifier(defaults: defaults),
        retryLimits: { _ in },
        navigation: SettingsNavigation()
    )
}
#endif
