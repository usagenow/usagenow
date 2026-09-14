import AppKit
import Observation

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
    let settingsNavigation = SettingsNavigation()

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
        widgetSnapshots: WidgetSnapshotWriter = WidgetSnapshotWriter()
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
        return AppState(
            providers: makeProviders(defaults: defaults, claudeLimits: claudeLimits),
            defaults: defaults,
            telemetryConfiguration: .current(defaults: defaults),
            claudeLimits: claudeLimits
        )
    }

    /// Real providers in production. Launch arguments such as
    /// `-UsageNowMockCodex critical` switch to mock providers with a
    /// deterministic `MockScenario` for development and QA.
    static func makeProviders(defaults: UserDefaults, claudeLimits: ClaudeLimitsControl?) -> [any UsageProvider] {
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
            // Percentages and reset times only, so they survive a relaunch between agy runs.
            AntigravityProvider(server: AgyLocalServer(lastKnownLimits: .userDefaults(defaults, key: "antigravityLastKnownLimits"))),
        ]
    }

    func start() {
        claudeLimits?.isEnabled.isOn = preferences.fetchClaudeUsageLimits
        Task { await store.refresh() }
        applyAppearance()
        applyRefreshInterval()

        observe({ [preferences] in _ = preferences.appearance }, apply: { [weak self] in self?.applyAppearance() })
        observe({ [preferences] in _ = preferences.refreshInterval }, apply: { [weak self] in self?.applyRefreshInterval() })
        observe({ [preferences] in _ = preferences.fetchClaudeUsageLimits }, apply: { [weak self] in self?.applyClaudeLimitsPreference() })
        observe({ [providerPreferences] in _ = providerPreferences.enabledProviders }, apply: { [weak self] in self?.applyEnabledProviders() })
        observe({ [providerPreferences] in _ = providerPreferences.order }, apply: { [weak self] in self?.applyProviderOrder() })
        observe({ [store] in _ = store.states }, apply: { [weak self] in self?.storeDidChange() })
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

    /// Asks Claude for limits now, including the keychain after an earlier failure.
    func retryClaudeLimits() {
        guard providerPreferences.isEnabled(.claudeCode) else { return }
        Task { [store] in await store.refresh(only: [.claudeCode], trigger: .manual) }
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
        widgetSnapshots.update(states: store.states, enabledProviders: store.enabledProviders)
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

/// Which Settings tab is shown. Lets the popover open a specific one.
@Observable
@MainActor
final class SettingsNavigation {
    var tab: SettingsTab = .general
}
