import SwiftUI

/// Hands the scene's "open Settings" action to code outside any scene.
private struct SettingsOpener: View {
    let capture: (@escaping @MainActor () -> Void) -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear { capture { openSettings() } }
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
        MenuBarExtra {
            MenuBarContentView(store: appState.store, navigation: appState.settingsNavigation)
                .appLanguage(appState.preferences.languageAtLaunch)
                .environment(\.usageAmountStyle, appState.preferences.usageAmountStyle)
                .environment(\.showsActivityHistory, appState.preferences.showsActivityHistory)
                .onPopoverOpen { appState.popoverDidOpen() }
        } label: {
            MenuBarLabel(preferences: appState.preferences, store: appState.store)
                .background(SettingsOpener { appState.openSettings = $0 })
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                preferences: appState.preferences,
                providerPreferences: appState.providerPreferences,
                analyticsPreferences: appState.analyticsPreferences,
                launchAtLogin: appState.launchAtLogin,
                updates: appState.updates,
                store: appState.store,
                limitNotifier: appState.limitNotifier,
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
}
