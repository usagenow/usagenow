import AppKit
import SwiftUI

enum SettingsTab: Hashable, Sendable {
    case general
    case providers
    case menuBar
    case privacy
    case about
}

struct SettingsView: View {
    static let width: CGFloat = 480

    let preferences: AppPreferences
    let providerPreferences: ProviderPreferences
    let analyticsPreferences: AnalyticsPreferences
    let launchAtLogin: LaunchAtLogin
    let store: UsageStore
    /// Asks an experimental limits source to try again, keychain included.
    let retryLimits: (ProviderID) -> Void
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView(
                    preferences: preferences,
                    providerPreferences: providerPreferences,
                    launchAtLogin: launchAtLogin,
                    store: store,
                    retryLimits: retryLimits
                )
            }
            Tab("Providers", systemImage: "circle.hexagongrid", value: SettingsTab.providers) {
                ProvidersSettingsView(preferences: providerPreferences)
            }
            Tab("Menu Bar", systemImage: "menubar.rectangle", value: SettingsTab.menuBar) {
                MenuBarSettingsView(preferences: preferences, providerPreferences: providerPreferences)
            }
            Tab("Privacy", systemImage: "hand.raised", value: SettingsTab.privacy) {
                PrivacySettingsView(analyticsPreferences: analyticsPreferences)
            }
            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutSettingsView()
            }
        }
        .frame(width: Self.width)
    }
}

struct GeneralSettingsView: View {
    @Bindable var preferences: AppPreferences
    let providerPreferences: ProviderPreferences
    let launchAtLogin: LaunchAtLogin
    let store: UsageStore
    let retryLimits: (ProviderID) -> Void

    /// Why a provider's quota is missing right now, if it is.
    private func quotaIssue(_ provider: ProviderID) -> QuotaUnavailableReason? {
        store.states.first { $0.provider == provider }?.snapshot?.quotaUnavailableReason
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
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
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

    var body: some View {
        Form {
            Section {
                Picker("Display", selection: $preferences.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.available(for: providerPreferences.enabledProviders)) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text("Shows the icon alone when no usage limit is available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
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

struct AboutSettingsView: View {
    @State private var isShowingLicenses = false

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

            Button("Open Source Licenses…") { isShowingLicenses = true }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .sheet(isPresented: $isShowingLicenses) {
            LicensesView()
        }
    }
}

extension QuotaUnavailableReason {
    /// One short sentence saying what to do. Providers keep the detailed
    /// diagnosis in their logs.
    func message(for provider: ProviderID) -> String {
        switch self {
        case .toolNotRunning where provider == .antigravity:
            String(localized: "Open Antigravity CLI to update usage limits.")
        case .toolNotRunning:
            String(localized: "Open \(provider.displayName) to update usage limits.")
        // Claude Code is the only provider with a sign-in-based source today.
        case .signInExpired:
            String(localized: "Refresh Claude Code from Terminal to view usage limits.")
        case .permissionDenied:
            String(localized: "Allow UsageNow to access your Claude Code sign-in in Keychain.")
        case .temporarilyUnavailable where provider == .antigravity:
            String(localized: "Antigravity usage limits are temporarily unavailable.")
        case .temporarilyUnavailable:
            String(localized: "Claude usage limits are temporarily unavailable.")
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
        store: PreviewFixtures.store(codex: .normal, claude: .normal),
        retryLimits: { _ in },
        navigation: SettingsNavigation()
    )
}
#endif
