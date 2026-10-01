import SwiftUI

@main
struct UsageNowApp: App {
    @State private var appState: AppState

    init() {
        // Writing to a pipe whose reader has exited — the Codex app-server
        // quitting early — raises SIGPIPE, which ends the app without a word.
        // Ignored, the write fails with an error the caller already handles.
        signal(SIGPIPE, SIG_IGN)
        let appState = AppState.live()
        appState.start()
        _appState = State(initialValue: appState)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: appState.store, navigation: appState.settingsNavigation)
                .environment(\.usageAmountStyle, appState.preferences.usageAmountStyle)
                .environment(\.showsActivityHistory, appState.preferences.showsActivityHistory)
                .onPopoverOpen { appState.popoverDidOpen() }
        } label: {
            MenuBarLabel(preferences: appState.preferences, store: appState.store)
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
                retryLimits: { appState.retryLimits(for: $0) },
                hasAPIKey: { appState.apiKeys.hasKey(for: $0) },
                setAPIKey: { try appState.setAPIKey($0, for: $1) },
                navigation: appState.settingsNavigation
            )
        }
    }
}
