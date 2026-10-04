import Foundation
import Testing

@testable import UsageNow

@MainActor
struct AppLanguageTests {
    @Test func readsTheLanguageMacOSKeepsForTheApp() {
        #expect(AppLanguage(preferredLanguages: ["ru-KZ"]) == .ru)
        #expect(AppLanguage(preferredLanguages: ["de"]) == .de)
        #expect(AppLanguage(preferredLanguages: ["ja"]) == .system)
        #expect(AppLanguage(preferredLanguages: nil) == .system)
    }

    @Test func namesEachLanguageInItself() {
        #expect(AppLanguage.allCases.compactMap(\.nativeName) == ["Deutsch", "English", "Español", "Français", "Русский"])
    }

    @Test func choosingALanguageSetsTheAppsOwnLanguageList() throws {
        let name = "language-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let preferences = AppPreferences(defaults: defaults, languageDomain: name)
        #expect(preferences.language == .system)

        preferences.language = .ru
        #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == ["ru"])
        #expect(preferences.languageAtLaunch == .system)

        let relaunched = AppPreferences(defaults: defaults, languageDomain: name)
        #expect(relaunched.language == .ru)
        #expect(relaunched.languageAtLaunch == .ru)

        relaunched.language = .system
        #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    }

    @Test func theWidgetIsToldTheLanguage() throws {
        let store = WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID())"))
        let writer = WidgetSnapshotWriter(store: store, reloadTimelines: {})
        writer.update(states: [], enabledProviders: [.codex], language: .fr)
        #expect(store.read()?.language == "fr")
        writer.update(states: [], enabledProviders: [.codex], language: .system)
        #expect(store.read()?.language == nil)
    }
}

@MainActor
struct SettingsWidthTests {
    /// The toolbar's titles must fit, or macOS hides the last tabs in an
    /// overflow menu where they can't be chosen.
    @Test func settingsWidenForLongerTabTitles() {
        let english = ["General", "Providers", "Menu Bar", "Notifications", "Privacy", "About"]
        let russian = ["Основные", "Провайдеры", "Строка меню", "Уведомления", "Конфиденциальность", "О программе"]
        #expect(SettingsView.toolbarWidth(for: english) == 480)
        #expect(SettingsView.toolbarWidth(for: russian) > 600)
    }
}
