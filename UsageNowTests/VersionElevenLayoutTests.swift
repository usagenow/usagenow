import AppKit
import SwiftUI
import Testing
@testable import UsageNow

@MainActor
struct VersionElevenLayoutTests {
    @Test func overviewAndAccountSetsRenderInEnglishRussianAndRTL() throws {
        let destination = URL(filePath: "/private/tmp/usagenow-1.1-ui", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let now = Date.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let records = (0..<30).map { index in
            ActivityRecord(key: "day-\(index)", timestamp: calendar.date(byAdding: .day, value: -index, to: now)!,
                tokens: Int64(10000 + index * 9000), model: index.isMultiple(of: 2) ? "claude-sonnet" : "model-b")
        }
        let history = ActivityHistory(records: records, period: ActivityPeriod(now: now, calendar: calendar))
        var codex = Fixtures.snapshot(.codex, at: now)
        codex.activity.history = history
        var claude = Fixtures.snapshot(.claudeCode, at: now)
        claude.activity.history = history
        let states = [ProviderState(provider: .codex, snapshot: codex), ProviderState(provider: .claudeCode, snapshot: claude)]
        let store = UsageStore(providers: [], enabledProviders: [.codex, .claudeCode], states: states, hasCompletedInitialLoad: true)
        for language in [AppLanguage.en, .ru, .he] {
            let defaults = UserDefaults(suiteName: "Layout1.1.\(UUID())")!
            let sets = AccountSets(defaults: defaults)
            sets.setMembership(true, source: SourceKey(provider: .codex), in: "work")
            for dark in [false, true] {
                let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
                let suffix = language.rawValue + (dark ? "-dark" : "-light")
                try render(OverviewView(store: store, accountSets: sets).appLanguage(language), width: 1000, height: 700,
                    appearance: appearance, to: destination.appending(path: "overview-\(suffix).png"))
                try render(AccountSetsSettingsView(sets: sets, states: states).appLanguage(language), width: 660, height: 490,
                    appearance: appearance, to: destination.appending(path: "sets-\(suffix).png"))
            }
        }
    }

    @Test func providerIconsAndMenuBarSettingsRenderInBothThemesAndRTL() throws {
        let destination = URL(filePath: "/private/tmp/usagenow-1.1-ui", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let now = Date.now
        let saved = UserDefaults(suiteName: "MenuBarLayout.\(UUID())")!
        let preferences = AppPreferences(defaults: saved)
        let providers = ProviderPreferences(defaults: saved)
        for provider in ProviderCatalog.availableIDs { providers.setEnabled([.codex, .claudeCode, .minimax, .perplexity].contains(provider), for: provider) }
        let account = ProviderAccount(id: "work", provider: .codex, name: "Work")
        providers.addAccount(account)
        var added = Fixtures.snapshot(.codex, fiveHour: 80, at: now)
        added.account = account.tag
        let states = [
            ProviderState(provider: .codex, snapshot: Fixtures.snapshot(.codex, fiveHour: 42, at: now)),
            ProviderState(provider: .codex, account: account.tag, snapshot: added),
            ProviderState(provider: .claudeCode, snapshot: Fixtures.snapshot(.claudeCode, fiveHour: 90, at: now),
                failure: RefreshFailure(message: "Offline", date: now)),
            ProviderState(provider: .minimax, snapshot: Fixtures.snapshot(.minimax, at: now)),
            ProviderState(provider: .perplexity, snapshot: Fixtures.snapshot(.perplexity, at: now)),
        ]
        preferences.menuBarItems = .init(layout: .providers, sources: [states[0].id, states[2].id, states[1].id, states[3].id])
        let store = UsageStore(providers: [], enabledProviders: providers.enabledProviders, states: states, hasCompletedInitialLoad: true)
        let sets = AccountSets(defaults: saved)
        for language in [AppLanguage.en, .ru, .he] {
            for dark in [false, true] {
                let suffix = language.rawValue + (dark ? "-dark" : "-light")
                let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
                try render(MenuBarSettingsView(preferences: preferences, providerPreferences: providers, store: store, accountSets: sets)
                    .appLanguage(language), width: 700, height: 580, appearance: appearance,
                    to: destination.appending(path: "menubar-settings-\(suffix).png"))
                let labels = HStack(spacing: 16) {
                    ForEach(states) { state in
                        ProviderMenuBarReadingLabel(reading: ProviderMenuBarReading(state: state, at: now), style: .remaining, now: now)
                    }
                }.padding(16).frame(width: 500, height: 60)
                try render(labels.appLanguage(language), width: 500, height: 60, appearance: appearance,
                    to: destination.appending(path: "menubar-labels-\(suffix).png"))
            }
        }
    }

    private func render(_ view: some View, width: CGFloat, height: CGFloat, appearance: NSAppearance.Name, to url: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        // Native List content needs a window to complete its layout. The
        // test window is never ordered onscreen and reads only fixtures.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(image.count > 1500)
        try image.write(to: url)
    }

    @Test func newCopyCoversEverySupportedLanguage() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appending(path: "scripts/translations-1.1.json")
        let data = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
        let keys = try #require(data["keys"] as? [String])
        let translations = try #require(data["translations"] as? [String: [String]])
        #expect(translations.count == 12)
        for values in translations.values {
            #expect(values.count == keys.count)
            #expect(values.allSatisfy { !$0.isEmpty })
        }
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "Shared/Resources/Localizable.xcstrings"))) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        for key in keys {
            let languages = try #require(strings[key]?["localizations"] as? [String: Any])
            #expect(Set(translations.keys).isSubset(of: Set(languages.keys)))
        }
    }
}
