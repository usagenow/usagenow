import AppKit
import Observation
import SwiftUI

/// Composition root: builds the app's long-lived services and wires them together.
@MainActor
final class AppState {
    /// Opening the popover refreshes only when the last refresh is older than this.
    static let popoverRefreshMaxAge: TimeInterval = 60

    let store: UsageStore
    let preferences: AppPreferences
    let providerPreferences: ProviderPreferences
    let analyticsPreferences: AnalyticsPreferences
    let launchAtLogin: LaunchAtLogin
    let updates: UpdateController
    /// The person's API keys for providers connected with one. Keychain only.
    let apiKeys: any APIKeyStoring
    let settingsNavigation = SettingsNavigation()
    let limitNotifier: LimitNotifier
    let hotKey = GlobalHotKey.shared
    /// SwiftUI's action for opening Settings, handed over by the menu bar
    /// label, which lives in a scene. The shortcut's panel doesn't.
    var openSettings: (@MainActor () -> Void)?
    private var shortcutPanel: ShortcutPanelController?

    /// Deliberately never given `store` or snapshots — only which providers
    /// are installed. See `TelemetryClient`.
    private let telemetry: TelemetryReporter
    private let widgetSnapshots: WidgetSnapshotWriter
    private let scheduler: AutoRefreshScheduler
    private let claudeLimits: ClaudeLimitsControl?

    /// The experimental Claude usage-limits source and its on/off switch.
    struct ClaudeLimitsControl: Sendable {
        let isEnabled: FeatureSwitch
        let client: ClaudeUsageLimitsClient
    }

    init(
        providers: [any UsageProvider],
        defaults: UserDefaults = .standard,
        telemetryConfiguration: TelemetryConfiguration = .disabled,
        identity: InstallationIdentity = InstallationIdentity(),
        claudeLimits: ClaudeLimitsControl? = nil,
        widgetSnapshots: WidgetSnapshotWriter = WidgetSnapshotWriter(),
        apiKeys: any APIKeyStoring = KeychainAPIKeyStore(),
        limitNotifier: LimitNotifier? = nil
    ) {
        let providerPreferences = ProviderPreferences(defaults: defaults)
        let store = UsageStore(providers: providers, enabledProviders: providerPreferences.enabledProviders, order: providerPreferences.order)
        let analyticsPreferences = AnalyticsPreferences(defaults: defaults)
        let client = NetworkTelemetryClient(
            configuration: telemetryConfiguration,
            identity: identity,
            isSharingEnabled: { @MainActor in analyticsPreferences.isSharingEnabled }
        )

        self.store = store
        self.preferences = AppPreferences(defaults: defaults)
        self.providerPreferences = providerPreferences
        self.analyticsPreferences = analyticsPreferences
        self.launchAtLogin = LaunchAtLogin()
        self.updates = UpdateController()
        self.apiKeys = apiKeys
        self.limitNotifier = limitNotifier ?? LimitNotifier(defaults: defaults)
        self.telemetry = TelemetryReporter(client: client, preferences: analyticsPreferences, identity: identity, defaults: defaults)
        self.claudeLimits = claudeLimits
        self.widgetSnapshots = widgetSnapshots
        self.scheduler = AutoRefreshScheduler { [weak store] in
            await store?.refresh()
        }
    }

    /// The app's runtime configuration.
    static func live(defaults: UserDefaults = .standard) -> AppState {
        let claudeLimits = ClaudeLimitsControl(
            isEnabled: FeatureSwitch(false),
            client: ClaudeUsageLimitsClient(
                // Percentages and reset times only, so a relaunch doesn't blank them.
                lastKnownLimits: .userDefaults(defaults, key: "experimental.claudeLastKnownLimits")
            )
        )
        let apiKeys = KeychainAPIKeyStore()
        return AppState(
            providers: makeProviders(defaults: defaults, claudeLimits: claudeLimits, apiKeys: apiKeys),
            defaults: defaults,
            telemetryConfiguration: .current(defaults: defaults),
            claudeLimits: claudeLimits,
            apiKeys: apiKeys
        )
    }

    /// Real providers in production. Launch arguments such as
    /// `-UsageNowMockCodex critical` switch to mock providers with a
    /// deterministic `MockScenario` for development and QA.
    static func makeProviders(defaults: UserDefaults, claudeLimits: ClaudeLimitsControl?, apiKeys: any APIKeyStoring) -> [any UsageProvider] {
        let codexScenario = defaults.string(forKey: "UsageNowMockCodex").flatMap(MockScenario.init(rawValue:))
        let claudeScenario = defaults.string(forKey: "UsageNowMockClaude").flatMap(MockScenario.init(rawValue:))
        let geminiScenario = defaults.string(forKey: "UsageNowMockGemini").flatMap(MockScenario.init(rawValue:))
        let antigravityScenario = defaults.string(forKey: "UsageNowMockAntigravity").flatMap(MockScenario.init(rawValue:))
        if codexScenario != nil || claudeScenario != nil || geminiScenario != nil || antigravityScenario != nil {
            return [
                MockCodexProvider(scenario: codexScenario ?? .normal),
                MockClaudeProvider(scenario: claudeScenario ?? .normal),
                MockGeminiProvider(scenario: geminiScenario ?? .normal),
                MockAntigravityProvider(scenario: antigravityScenario ?? .normal),
            ]
        }
        return [
            CodexProvider(),
            ClaudeCodeProvider(limitsClient: claudeLimits?.client, limitsEnabled: claudeLimits?.isEnabled ?? FeatureSwitch(false)),
            GeminiProvider(),
            // Percentages and reset times only, so they survive a relaunch between app runs.
            AntigravityProvider(server: AntigravityLocalServer(lastKnownLimits: .userDefaults(defaults, key: "antigravityLastKnownLimits"))),
            KiroProvider(),
            WarpProvider(),
            OpenCodeProvider(),
            QoderProvider(),
            QwenCodeProvider(),
            ClineProvider(),
            GrokBuildProvider(),
            APIKeyProvider.deepSeek(keys: apiKeys),
            APIKeyProvider.kimi(keys: apiKeys),
            APIKeyProvider.openRouter(keys: apiKeys),
            APIKeyProvider.ollama(keys: apiKeys),
        ]
    }

    func start() {
        claudeLimits?.isEnabled.isOn = preferences.fetchClaudeUsageLimits
        Task { [store] in
            await store.refresh()
            // The first refresh reads a month of session files, and the
            // allocator keeps the freed read buffers for reuse — shown as
            // ~170 MB more in Activity Monitor. Later refreshes read only new
            // lines, so hand that memory back to the system now.
            malloc_zone_pressure_relief(nil, 0)
        }
        applyAppearance()
        applyRefreshInterval()
        applyLimitNotifications()
        hotKey.action = { [weak self] in self?.toggleShortcutPanel() }
        applyPopoverShortcut()

        observe({ [preferences] in _ = preferences.appearance }, apply: { [weak self] in self?.applyAppearance() })
        observe({ [preferences] in _ = preferences.refreshInterval }, apply: { [weak self] in self?.applyRefreshInterval() })
        observe({ [preferences] in _ = preferences.fetchClaudeUsageLimits }, apply: { [weak self] in self?.applyClaudeLimitsPreference() })
        observe({ [providerPreferences] in _ = providerPreferences.enabledProviders }, apply: { [weak self] in self?.applyEnabledProviders() })
        observe({ [providerPreferences] in _ = providerPreferences.order }, apply: { [weak self] in self?.applyProviderOrder() })
        observe({ [store] in _ = store.states }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [preferences] in _ = preferences.usageAmountStyle }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [preferences] in _ = preferences.showsActivityHistory }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [preferences] in _ = preferences.notifiesAboutLimits }, apply: { [weak self] in self?.applyLimitNotifications() })
        observe({ [preferences] in _ = preferences.popoverShortcut }, apply: { [weak self] in self?.applyPopoverShortcut() })
        observe({ [analyticsPreferences] in _ = analyticsPreferences.isSharingEnabled }, apply: { [weak self] in self?.analyticsSharingChanged() })

        Task { [telemetry] in await telemetry.appDidBecomeActive() }
    }

    func popoverDidOpen() {
        Task { await store.refreshIfNeeded(maxAge: Self.popoverRefreshMaxAge) }
        Task { [telemetry] in await telemetry.appDidBecomeActive() }
    }

    /// Applied app-wide so the popover and Settings always match.
    private func applyAppearance() {
        NSApplication.shared.appearance = switch preferences.appearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }

    /// Applies a change in which providers are tracked, and keeps the menu
    /// bar showing a provider that's still enabled.
    private func applyEnabledProviders() {
        let enabled = providerPreferences.enabledProviders
        // Turning off a provider connected with a key forgets the key.
        for definition in ProviderCatalog.available where definition.apiKey != nil && !enabled.contains(definition.id) {
            try? apiKeys.removeKey(for: definition.id)
        }
        if let required = preferences.menuBarDisplayMode.requiredProvider, !enabled.contains(required) {
            preferences.menuBarDisplayMode = .default
        }
        Task { [store] in await store.setEnabledProviders(enabled) }
    }

    /// The popover and widget follow the order set in Settings.
    private func applyProviderOrder() {
        store.setProviderOrder(providerPreferences.order)
    }

    /// Turning the feature on fetches right away (macOS asks for keychain
    /// access then); turning it off forgets the token and cached limits.
    private func applyClaudeLimitsPreference() {
        guard let claudeLimits, providerPreferences.isEnabled(.claudeCode) else { return }
        let isEnabled = preferences.fetchClaudeUsageLimits
        claudeLimits.isEnabled.isOn = isEnabled
        Task { [store] in
            if !isEnabled { await claudeLimits.client.reset() }
            await store.refresh(only: [.claudeCode], trigger: isEnabled ? .manual : .automatic)
        }
    }

    /// Asks an experimental limits source for limits now.
    func retryLimits(for provider: ProviderID) {
        if provider == .claudeCode { retryClaudeLimits() }
    }

    /// Saves or clears a provider's API key, then reads the provider with it.
    func setAPIKey(_ key: String?, for provider: ProviderID) throws {
        if let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try apiKeys.setKey(key, for: provider)
        } else {
            try apiKeys.removeKey(for: provider)
        }
        guard providerPreferences.isEnabled(provider) else { return }
        Task { [store] in await store.refresh(only: [provider], trigger: .manual) }
    }

    /// Asks Claude for limits now, including the keychain after an earlier failure.
    func retryClaudeLimits() {
        guard providerPreferences.isEnabled(.claudeCode) else { return }
        Task { [store] in await store.refresh(only: [.claudeCode], trigger: .manual) }
    }

    /// Turning notifications on asks macOS for permission — once — and
    /// looks at the limits already on screen.
    private func applyLimitNotifications() {
        let isEnabled = preferences.notifiesAboutLimits
        limitNotifier.setEnabled(isEnabled)
        guard isEnabled else { return }
        Task { [weak self] in
            await self?.limitNotifier.requestPermission()
            self?.notifyAboutLimits()
        }
    }

    private func notifyAboutLimits() {
        limitNotifier.update(snapshots: store.snapshots, enabledProviders: store.enabledProviders, style: preferences.usageAmountStyle)
    }

    private func toggleShortcutPanel() {
        if shortcutPanel == nil {
            shortcutPanel = ShortcutPanelController(
                content: { [unowned self] in AnyView(ShortcutPanelContent(appState: self)) },
                onOpen: { [weak self] in self?.popoverDidOpen() }
            )
        }
        shortcutPanel?.toggle()
    }

    private func applyPopoverShortcut() {
        hotKey.register(preferences.popoverShortcut)
    }

    private func applyRefreshInterval() {
        scheduler.schedule(every: preferences.refreshInterval.duration)
    }

    /// Installed providers, as plain identifiers — the only provider fact telemetry sees.
    private var detectedProviders: Set<ProviderID> {
        Set(store.snapshots.filter { $0.status != .notInstalled }.map(\.provider))
    }

    private func storeDidChange() {
        let detected = detectedProviders
        Task { [telemetry] in await telemetry.providersDetected(detected) }
        // The widget only ever sees what this writer publishes.
        widgetSnapshots.update(
            states: store.states,
            enabledProviders: store.enabledProviders,
            style: preferences.usageAmountStyle,
            includesRecentDays: preferences.showsActivityHistory
        )
        notifyAboutLimits()
    }

    private func analyticsSharingChanged() {
        let detected = detectedProviders
        Task { [telemetry] in await telemetry.sharingDidChange(detectedProviders: detected) }
    }

    /// Calls `apply` every time a value read in `read` changes.
    private func observe(
        _ read: @escaping @MainActor @Sendable () -> Void,
        apply: @escaping @MainActor @Sendable () -> Void
    ) {
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                apply()
                self?.observe(read, apply: apply)
            }
        }
    }
}

/// The menu bar window's content, for the panel the shortcut opens. Reads
/// the same preferences, so both windows always look alike.
private struct ShortcutPanelContent: View {
    let appState: AppState

    var body: some View {
        MenuBarContentView(
            store: appState.store,
            navigation: appState.settingsNavigation,
            openSettingsOverride: appState.openSettings
        )
        .environment(\.usageAmountStyle, appState.preferences.usageAmountStyle)
        .environment(\.showsActivityHistory, appState.preferences.showsActivityHistory)
    }
}

/// Which Settings tab is shown. Lets the popover open a specific one.
@Observable
@MainActor
final class SettingsNavigation {
    var tab: SettingsTab = .general
}
