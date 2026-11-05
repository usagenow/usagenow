import SwiftUI

/// Hands the scene's "open Settings" action to code outside any scene.
private struct SettingsOpener: View {
    let capture: (@escaping @MainActor () -> Void) -> Void
    var captureOverview: (@escaping @MainActor () -> Void) -> Void = { _ in }
    var needsSetup = false

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            capture { openSettings() }
            captureOverview { openWindow(id: "overview"); NSApplication.shared.activate() }
            if needsSetup { openWindow(id: "setup") }
        }
    }
}

@main
struct UsageNowApp: App {
    @State private var appState: AppState

    init() {
        // Writing to a pipe whose reader has exited — the Codex app-server
        // quitting early — raises SIGPIPE, which ends the app without a word.
        // Ignored, the write fails with an error the caller already handles.
        signal(SIGPIPE, SIG_IGN)
        // Hosted unit tests must not launch real providers, touch sign-ins,
        // or publish synthetic data to a desktop widget.
        let isTesting = UserDefaults.standard.bool(forKey: "UsageNowTesting")
        let appState = isTesting
            ? AppState(providers: [], widgetSnapshots: WidgetSnapshotWriter(store: nil))
            : AppState.live()
        if !isTesting { appState.start() }
        _appState = State(initialValue: appState)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { providerSources.isEmpty }, set: { _ in })) {
            menuBarContent()
        } label: {
            MenuBarLabel(preferences: appState.preferences, store: appState.store, accountSets: appState.accountSets)
                .background(SettingsOpener(capture: { appState.openSettings = $0 }, captureOverview: { appState.openOverview = $0 }, needsSetup: appState.firstRun.needsSetup))
        }
        .menuBarExtraStyle(.window)

        // Stable scenes, rather than more app runtimes. Slot contents follow
        // the person's selection/order and all share AppState's one store.
        providerMenuBarExtra(slot: 0)
        providerMenuBarExtra(slot: 1)
        providerMenuBarExtra(slot: 2)
        providerMenuBarExtra(slot: 3)

        Window("Overview", id: "overview") {
            OverviewView(store: appState.store, accountSets: appState.accountSets)
                .appLanguage(appState.preferences.languageAtLaunch)
        }
        .defaultSize(width: 960, height: 700)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Welcome to UsageNow", id: "setup") {
            FirstRunView(preferences: appState.providerPreferences, finish: { appState.firstRun.complete() }, connect: {
                appState.settingsNavigation.tab = .providers
                appState.openSettings?()
            })
            .appLanguage(appState.preferences.languageAtLaunch)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(
                preferences: appState.preferences,
                providerPreferences: appState.providerPreferences,
                analyticsPreferences: appState.analyticsPreferences,
                launchAtLogin: appState.launchAtLogin,
                updates: appState.updates,
                store: appState.store,
                limitNotifier: appState.limitNotifier,
                accountSets: appState.accountSets,
                hotKey: appState.hotKey,
                retryLimits: { appState.retryLimits(for: $0) },
                hasAPIKey: { appState.apiKeys.hasKey(for: $0, account: $1) },
                setAPIKey: { try appState.setAPIKey($0, for: $1, account: $2) },
                removeAccount: { appState.removeAccount($0) },
                navigation: appState.settingsNavigation
            )
            .appLanguage(appState.preferences.languageAtLaunch)
        }
    }

    private var providerSources: [SourceKey] {
        guard !appState.firstRun.needsSetup else { return [] }
        return appState.preferences.menuBarItems.visibleSources(in: appState.store.states,
            enabled: appState.store.enabledProviders, set: appState.accountSets.active)
    }

    private func source(at slot: Int) -> SourceKey? {
        let sources = providerSources
        return sources.indices.contains(slot) ? sources[slot] : nil
    }

    private func providerMenuBarExtra(slot: Int) -> some Scene {
        let source = source(at: slot)
        return MenuBarExtra(isInserted: Binding(get: { source != nil }, set: { inserted in
            if !inserted, let source {
                appState.preferences.menuBarItems.select(source, included: false)
            }
        })) {
            menuBarContent(focusedSource: source)
        } label: {
            Group {
                if let source {
                    ProviderMenuBarLabel(source: source, store: appState.store, preferences: appState.preferences)
                }
            }
            .background(SettingsOpener(capture: { appState.openSettings = $0 }, captureOverview: { appState.openOverview = $0 }))
        }
        .menuBarExtraStyle(.window)
    }

    private func menuBarContent(focusedSource: SourceKey? = nil) -> some View {
        MenuBarContentView(store: appState.store, serviceHealth: appState.serviceHealth,
            navigation: appState.settingsNavigation, accountSets: appState.accountSets, focusedSource: focusedSource)
            .appLanguage(appState.preferences.languageAtLaunch)
            .environment(\.usageAmountStyle, appState.preferences.usageAmountStyle)
            .environment(\.showsActivityHistory, appState.preferences.showsActivityHistory)
            .onPopoverOpen { appState.popoverDidOpen() }
    }
}
