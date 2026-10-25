import Foundation
import Testing

@testable import UsageNow

@MainActor
struct AppLanguageTests {
    @Test func readsTheLanguageMacOSKeepsForTheApp() {
        #expect(AppLanguage(preferredLanguages: ["ru-KZ"]) == .ru)
        #expect(AppLanguage(preferredLanguages: ["de"]) == .de)
        #expect(AppLanguage(preferredLanguages: ["pt-BR"]) == .pt)
        #expect(AppLanguage(preferredLanguages: ["nl-NL"]) == .nl)
        #expect(AppLanguage(preferredLanguages: ["nl-BE"]) == .nl)
        #expect(AppLanguage(preferredLanguages: ["he-IL"]) == .he)
        #expect(AppLanguage(preferredLanguages: ["kk-KZ"]) == .kk)
        #expect(AppLanguage(preferredLanguages: ["uz-Latn-UZ"]) == .uz)
        #expect(AppLanguage(preferredLanguages: ["tr-TR"]) == .tr)
        #expect(AppLanguage(preferredLanguages: ["zh-Hans"]) == .system)
        #expect(AppLanguage(preferredLanguages: nil) == .system)
    }

    @Test func namesEachLanguageInItself() {
        #expect(AppLanguage.allCases.compactMap(\.nativeName) == [
            "Deutsch", "English", "Español", "Français", "Nederlands", "Özbekça", "Português", "Türkçe", "Қазақша", "Русский", "עברית", "日本語", "한국어",
        ])
    }

    @Test func onlyHebrewReadsRightToLeft() {
        #expect(AppLanguage.allCases.filter(\.isRightToLeft) == [.he])
    }

    @Test func dutchResourcesAreBundledForAppAndWidgetCopy() throws {
        #expect(Bundle.main.localizations.contains("nl"))
        let path = try #require(Bundle.main.path(forResource: "nl", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        for (key, value) in ["General": "Algemeen", "Quota pace": "Verbruikstempo", "Done": "Gereed"] {
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == value)
        }
    }

    @Test func newLanguagesBundleRealTextAndUzbekSpelling() throws {
        for (language, expected) in [("kk", "Жалпы"), ("uz", "Umumiy"), ("tr", "Genel")] {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: "General", value: nil, table: nil) == expected)
        }
        let path = try #require(Bundle.main.path(forResource: "uz", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        #expect(bundle.localizedString(forKey: "Choose your providers", value: nil, table: nil) == "Provayderlaringizni tanlang")
        #expect(bundle.localizedString(forKey: "Skip Setup", value: nil, table: nil) == "Sozlaşni ötkaziş")
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
        writer.update(states: [], enabledProviders: [.codex], language: .nl)
        #expect(store.read()?.language == "nl")
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
