import AppKit
import Observation
import SwiftUI

/// Composition root: builds the app's long-lived services and wires them together.
@MainActor
final class AppState {
    /// Opening the popover refreshes only when the last refresh is older than this.
    static let popoverRefreshMaxAge: TimeInterval = 60

    let store: UsageStore
    let firstRun: FirstRunSetup
    let serviceHealth: ServiceHealthStore
    let preferences: AppPreferences
    let providerPreferences: ProviderPreferences
    let accountSets: AccountSets
    let analyticsPreferences: AnalyticsPreferences
    let launchAtLogin: LaunchAtLogin
    let updates: UpdateController
    /// The person's API keys for providers connected with one. Keychain only.
    let apiKeys: any APIKeyStoring
    let settingsNavigation = SettingsNavigation()
    let limitNotifier: LimitNotifier
    let financialNotifier: FinancialNotifier
    let hotKey = GlobalHotKey.shared
    /// SwiftUI's action for opening Settings, handed over by the menu bar
    /// label, which lives in a scene. The shortcut's panel doesn't.
    var openSettings: (@MainActor () -> Void)?
    var openOverview: (@MainActor () -> Void)?
    private var shortcutPanel: ShortcutPanelController?
    private var wakeObserver: (any NSObjectProtocol)?
    private var timeZoneObserver: (any NSObjectProtocol)?

    /// Deliberately never given `store` or snapshots — only which providers
    /// are installed. See `TelemetryClient`.
    private let telemetry: TelemetryReporter
    private let widgetSnapshots: WidgetSnapshotWriter
    private let scheduler: AutoRefreshScheduler
    let refreshConditions = RefreshConditions()
    private var adaptiveScheduler: AdaptiveRefreshScheduler?
    private let claudeLimits: ClaudeLimitsControl?
    /// Builds the provider that reads an added account, or `nil` when it
    /// can't be read (mock providers).
    private let accountProvider: @Sendable (ProviderAccount) -> (any UsageProvider)?
    /// The provider reading each added account, kept while the account is
    /// unchanged so its caches survive another account being added.
    private var accountProviders: [ProviderAccount: any UsageProvider] = [:]

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
        limitNotifier: LimitNotifier? = nil,
        serviceHealth: ServiceHealthStore = ServiceHealthStore(),
        accountProvider: @escaping @Sendable (ProviderAccount) -> (any UsageProvider)? = { _ in nil }
    ) {
        firstRun = FirstRunSetup(defaults: defaults)
        let preferences = AppPreferences(defaults: defaults)
        let providerPreferences = ProviderPreferences(defaults: defaults)
        var accountProviders: [ProviderAccount: any UsageProvider] = [:]
        for account in providerPreferences.accounts {
            accountProviders[account] = accountProvider(account)
        }
        let store = UsageStore(
            providers: providers + providerPreferences.accounts.compactMap { accountProviders[$0] },
            enabledProviders: providerPreferences.enabledProviders,
            order: providerPreferences.order,
            quotaHistory: QuotaHistory(defaults: defaults)
        )
        let analyticsPreferences = AnalyticsPreferences(defaults: defaults)
        let client = NetworkTelemetryClient(
            configuration: telemetryConfiguration,
            identity: identity,
            isSharingEnabled: { @MainActor in analyticsPreferences.isSharingEnabled }
        )

        self.store = store
        self.serviceHealth = serviceHealth
        self.preferences = preferences
        // Also validate persisted selections at launch: the chosen account
        // may have been removed since this build last ran.
        self.preferences.menuBarChoice = self.preferences.menuBarChoice.validated(against: providerPreferences.accounts)
        self.preferences.menuBarItems = self.preferences.menuBarItems.validated(against: providerPreferences.accounts)
        self.providerPreferences = providerPreferences
        self.accountSets = AccountSets(defaults: defaults)
        self.accountSets.reconcile(accounts: providerPreferences.accounts)
        self.analyticsPreferences = analyticsPreferences
        self.launchAtLogin = LaunchAtLogin()
        self.updates = UpdateController()
        self.apiKeys = apiKeys
        self.limitNotifier = limitNotifier ?? LimitNotifier(defaults: defaults)
        self.financialNotifier = FinancialNotifier(defaults: defaults)
        self.telemetry = TelemetryReporter(client: client, preferences: analyticsPreferences, identity: identity, defaults: defaults)
        self.claudeLimits = claudeLimits
        self.accountProvider = accountProvider
        self.accountProviders = accountProviders
        self.widgetSnapshots = widgetSnapshots
        self.scheduler = AutoRefreshScheduler { [weak store, weak serviceHealth] in
            await store?.refresh()
            await serviceHealth?.refreshIfNeeded()
        }
        self.adaptiveScheduler = AdaptiveRefreshScheduler(states: { [weak store] in store?.states ?? [] },
            enabled: { [weak store] in store?.enabledProviders ?? [] },
            conditions: { [weak self] in self?.refreshConditions.value ?? .init() },
            refresh: { [weak store, weak serviceHealth] due in
                await store?.refresh(sources: due)
                await serviceHealth?.refreshIfNeeded()
            })
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
        let isMocked = usesMockProviders(defaults: defaults)
        return AppState(
            providers: makeProviders(defaults: defaults, claudeLimits: claudeLimits, apiKeys: apiKeys),
            defaults: defaults,
            telemetryConfiguration: .current(defaults: defaults),
            claudeLimits: claudeLimits,
            apiKeys: apiKeys,
            accountProvider: { isMocked ? nil : makeAccountProvider($0, apiKeys: apiKeys) }
        )
    }

    private static let mockArguments = ["UsageNowMockCodex", "UsageNowMockClaude", "UsageNowMockGemini", "UsageNowMockAntigravity"]

    static func usesMockProviders(defaults: UserDefaults) -> Bool {
        mockArguments.contains { defaults.string(forKey: $0).flatMap(MockScenario.init(rawValue:)) != nil }
    }

    /// The provider that reads an added account.
    nonisolated static func makeAccountProvider(_ account: ProviderAccount, apiKeys: any APIKeyStoring) -> (any UsageProvider)? {
        switch account.provider {
        case .codex: CodexProvider.reading(account)
        case .claudeCode: ClaudeCodeProvider.reading(account)
        default: APIKeyProvider.connected(account.provider, keys: apiKeys)?.reading(account)
        }
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
            AntigravityProvider(
                server: AntigravityLocalServer(lastKnownLimits: .userDefaults(defaults, key: "antigravityLastKnownLimits")),
                cli: AntigravityCLI(lastKnownLimits: .userDefaults(defaults, key: "antigravityCLILastKnownLimits"))
            ),
            KiroProvider(),
            WarpProvider(),
            OpenCodeProvider(),
            QoderProvider(),
            QwenCodeProvider(),
            ClineProvider(),
            GrokBuildProvider(),
            WindsurfProvider(),
            JetBrainsProvider(),
            APIKeyProvider.deepSeek(keys: apiKeys),
            APIKeyProvider.kimi(keys: apiKeys),
            APIKeyProvider.openRouter(keys: apiKeys),
            APIKeyProvider.ollama(keys: apiKeys),
            APIKeyProvider.cursor(keys: apiKeys),
            APIKeyProvider.copilot(keys: apiKeys),
            APIKeyProvider.perplexity(keys: apiKeys),
            APIKeyProvider.elevenLabs(keys: apiKeys),
            APIKeyProvider.zai(keys: apiKeys),
            APIKeyProvider.miniMax(keys: apiKeys),
        ]
    }

    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.preferences.refreshInterval == .adaptive { await self?.adaptiveScheduler?.tick(afterWake: true) }
                else { self?.popoverDidOpen() }
            }
        }
        timeZoneObserver = NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.notifyAboutLimits() }
        }
        claudeLimits?.isEnabled.isOn = preferences.fetchClaudeUsageLimits
        if !firstRun.needsSetup { startReadings() }
        applyAppearance()
        applyLimitNotifications()
        applyServiceStatusPreference()
        hotKey.action = { [weak self] in self?.toggleShortcutPanel() }
        applyPopoverShortcut()

        observe({ [firstRun] in _ = firstRun.needsSetup }, apply: { [weak self] in
            if self?.firstRun.needsSetup == false { self?.startReadings() }
        })

        observe({ [preferences] in _ = preferences.appearance }, apply: { [weak self] in self?.applyAppearance() })
        observe({ [preferences] in _ = preferences.refreshInterval }, apply: { [weak self] in self?.applyRefreshInterval() })
        observe({ [preferences] in _ = preferences.fetchClaudeUsageLimits }, apply: { [weak self] in self?.applyClaudeLimitsPreference() })
        observe({ [providerPreferences] in _ = providerPreferences.enabledProviders }, apply: { [weak self] in self?.applyEnabledProviders() })
        observe({ [providerPreferences] in _ = providerPreferences.order }, apply: { [weak self] in self?.applyProviderOrder() })
        observe({ [providerPreferences] in _ = providerPreferences.accounts }, apply: { [weak self] in self?.applyAccounts() })
        observe({ [accountSets] in _ = accountSets.selectedID; _ = accountSets.sets }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [store] in _ = store.states }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [preferences] in _ = preferences.usageAmountStyle }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [preferences] in _ = preferences.showsActivityHistory }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [preferences] in _ = preferences.showsServiceStatus }, apply: { [weak self] in self?.applyServiceStatusPreference() })
        observe({ [preferences] in _ = preferences.language }, apply: { [weak self] in self?.storeDidChange() })
        observe({ [preferences] in _ = preferences.notifiesAboutLimits }, apply: { [weak self] in self?.applyLimitNotifications() })
        observe({ [limitNotifier] in _ = limitNotifier.permission }, apply: { [weak self] in self?.notifyAboutLimits() })
        observe({ [preferences] in _ = preferences.notificationPolicy }, apply: { [weak self] in self?.notifyAboutLimits() })
        observe({ [preferences] in _ = preferences.financialPolicy }, apply: { [weak self] in self?.notifyAboutLimits() })
        observe({ [preferences] in _ = preferences.popoverShortcut }, apply: { [weak self] in self?.applyPopoverShortcut() })
        observe({ [analyticsPreferences] in _ = analyticsPreferences.isSharingEnabled }, apply: { [weak self] in self?.analyticsSharingChanged() })

        Task { [telemetry] in await telemetry.appDidBecomeActive() }
    }

    private func startReadings() {
        refreshConditions.start()
        Task { [store] in
            await store.refresh()
            // The first refresh reads a month of session files, and the
            // allocator keeps the freed read buffers for reuse — shown as
            // ~170 MB more in Activity Monitor. Later refreshes read only new
            // lines, so hand that memory back to the system now.
            malloc_zone_pressure_relief(nil, 0)
        }
        applyRefreshInterval()
    }

    func popoverDidOpen() {
        guard !firstRun.needsSetup else { return }
        if preferences.refreshInterval == .adaptive { Task { await adaptiveScheduler?.tick() } }
        else { Task { await store.refreshIfNeeded(maxAge: Self.popoverRefreshMaxAge) } }
        Task { await serviceHealth.refreshIfNeeded() }
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
        applyServiceStatusPreference()
        // Turning off a provider connected with a key forgets the key, and
        // the accounts added with keys of their own.
        for definition in ProviderCatalog.available where definition.apiKey != nil && !enabled.contains(definition.id) {
            try? apiKeys.removeKey(for: definition.id)
            for account in providerPreferences.accounts(for: definition.id) {
                try? apiKeys.removeKey(for: definition.id, account: account.id)
            }
            providerPreferences.removeAccounts(of: definition.id)
        }
        if let required = preferences.menuBarDisplayMode.requiredProvider, !enabled.contains(required) {
            preferences.menuBarChoice = .default
        }
        Task { [store] in await store.setEnabledProviders(enabled) }
    }

    private func applyServiceStatusPreference() {
        serviceHealth.configure(enabled: preferences.showsServiceStatus, providers: providerPreferences.enabledProviders)
        Task { [serviceHealth] in await serviceHealth.refreshIfNeeded() }
    }

    /// An account added in Settings is read right away; a removed one
    /// disappears, its key with it.
    private func applyAccounts() {
        let accounts = providerPreferences.accounts
        accountSets.reconcile(accounts: accounts)
        preferences.menuBarItems = preferences.menuBarItems.validated(against: accounts)
        let valid = Set(ProviderCatalog.available.map { SourceKey(provider: $0.id).description }
            + accounts.map { SourceKey(provider: $0.provider, account: $0.id).description })
        let keptRules = preferences.financialPolicy.rules.filter { valid.contains($0.key) }
        if keptRules != preferences.financialPolicy.rules { preferences.financialPolicy.rules = keptRules }
        // A removed account's menu bar choice falls back to the provider's own.
        let choice = preferences.menuBarChoice.validated(against: accounts)
        if choice != preferences.menuBarChoice { preferences.menuBarChoice = choice }
        var kept: [ProviderAccount: any UsageProvider] = [:]
        for account in accounts {
            kept[account] = accountProviders[account] ?? accountProvider(account)
        }
        accountProviders = kept
        let providers = accounts.compactMap { kept[$0] }
        Task { [store] in await store.setAccounts(providers) }
    }

    /// Removes an added account, and its key if it has one.
    func removeAccount(_ account: ProviderAccount) {
        financialNotifier.forget(SourceKey(provider: account.provider, account: account.id))
        try? apiKeys.removeKey(for: account.provider, account: account.id)
        providerPreferences.removeAccount(id: account.id)
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

    /// Saves or clears a provider's API key — its first account's, or an
    /// added account's — then reads the provider with it.
    func setAPIKey(_ key: String?, for provider: ProviderID, account: String? = nil) throws {
        if let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let connection = ProviderCatalog.definition(for: provider).apiKey
            let value = try connection?.normalizedCredential(key) ?? key
            try apiKeys.setKey(value, for: provider, account: account)
        } else {
            try apiKeys.removeKey(for: provider, account: account)
        }
        store.connectionDidChange(provider: provider, account: account)
        financialNotifier.forget(SourceKey(provider: provider, account: account))
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
        if !isEnabled { notifyAboutLimits() }
        guard isEnabled else { return }
        Task { [weak self] in
            await self?.limitNotifier.requestPermission()
            self?.notifyAboutLimits()
        }
    }

    private func notifyAboutLimits() {
        if !preferences.notifiesAboutLimits || limitNotifier.permission == .allowed {
            financialNotifier.update(states: store.states, enabledProviders: store.enabledProviders,
                enabled: preferences.notifiesAboutLimits,
                policy: preferences.financialPolicy, quietHours: preferences.notificationPolicy)
        }
        limitNotifier.update(snapshots: store.snapshots, enabledProviders: store.enabledProviders, style: preferences.usageAmountStyle,
                             policy: preferences.notificationPolicy,
                             activeSources: Set(store.states.filter { store.enabledProviders.contains($0.provider) }.map(\.id)))
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
        guard !firstRun.needsSetup else { return }
        adaptiveScheduler?.stop()
        scheduler.schedule(every: preferences.refreshInterval.duration)
        if preferences.refreshInterval == .adaptive { adaptiveScheduler?.start() }
    }

    /// Installed providers, as plain identifiers — the only provider fact telemetry sees.
    private var detectedProviders: Set<ProviderID> {
        Set(store.snapshots.filter { $0.status != .notInstalled }.map(\.provider))
    }

    private func storeDidChange() {
        adaptiveScheduler?.observe()
        let detected = detectedProviders
        Task { [telemetry] in await telemetry.providersDetected(detected) }
        // The widget only ever sees what this writer publishes.
        widgetSnapshots.update(
            states: store.states,
            enabledProviders: store.enabledProviders,
            style: preferences.usageAmountStyle,
            includesRecentDays: preferences.showsActivityHistory,
            language: preferences.language,
            followedSelectionIDs: accountSets.active.map { _ in
                accountSets.displaying(store.states, enabled: store.enabledProviders).map(WidgetSnapshotWriter.selectionID)
            }
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
            serviceHealth: appState.serviceHealth,
            navigation: appState.settingsNavigation,
            accountSets: appState.accountSets,
            openOverviewOverride: appState.openOverview,
            openSettingsOverride: appState.openSettings
        )
        .appLanguage(appState.preferences.languageAtLaunch)
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
