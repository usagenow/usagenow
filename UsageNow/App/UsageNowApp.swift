import SwiftUI

@main
struct UsageNowApp: App {
    @State private var appState: AppState

    init() {
        let appState = AppState.live()
        appState.start()
        _appState = State(initialValue: appState)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: appState.store, navigation: appState.settingsNavigation)
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
                store: appState.store,
                retryClaudeLimits: { appState.retryClaudeLimits() },
                navigation: appState.settingsNavigation
            )
        }
    }
}
