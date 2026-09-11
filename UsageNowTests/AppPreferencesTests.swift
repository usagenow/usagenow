import Foundation
import Testing
@testable import UsageNow

@MainActor
struct AppPreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaults() {
        let preferences = AppPreferences(defaults: makeDefaults())
        #expect(preferences.appearance == .light)
        #expect(preferences.refreshInterval == .fiveMinutes)
        #expect(preferences.menuBarDisplayMode == .iconOnly)
    }

    @Test func persistsChanges() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        preferences.appearance = .dark
        preferences.refreshInterval = .thirtyMinutes

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.refreshInterval == .thirtyMinutes)
    }

    @Test func ignoresInvalidStoredValues() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: "appearance")
        defaults.set(42, forKey: "refreshInterval")
        defaults.set("tickerTape", forKey: "menuBarDisplayMode")

        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.appearance == .light)
        #expect(preferences.refreshInterval == .fiveMinutes)
        #expect(preferences.menuBarDisplayMode == .iconOnly)
    }

    @Test func percentageModesPersist() {
        let defaults = makeDefaults()
        AppPreferences(defaults: defaults).menuBarDisplayMode = .codexPercentage
        #expect(AppPreferences(defaults: defaults).menuBarDisplayMode == .codexPercentage)
    }

    @Test func experimentalClaudeLimitsAreOffByDefault() {
        #expect(AppPreferences(defaults: makeDefaults()).fetchClaudeUsageLimits == false)
    }

    @Test func analyticsAreOffByDefault() {
        #expect(AnalyticsPreferences(defaults: makeDefaults()).isSharingEnabled == false)
    }
}
