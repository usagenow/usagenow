import AppKit
import SwiftUI
import Testing
@testable import UsageNow

@MainActor
struct VersionOneLayoutTests {
    @Test func newScreensRenderInNewLanguagesAndRTL() throws {
        let destination = URL(fileURLWithPath: "/private/tmp/usagenow-1.0-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for language in [AppLanguage.kk, .uz, .tr, .ru, .he] {
            let saved = UserDefaults(suiteName: "layout.\(UUID())")!
            let preferences = AppPreferences(defaults: saved)
            preferences.notifiesAboutLimits = true
            preferences.notificationPolicy.quietHoursEnabled = true
            try render(FirstRunView(preferences: ProviderPreferences(defaults: saved), finish: {}, connect: {}).appLanguage(language),
                       width: 510, height: 480, to: destination.appending(path: "setup-\(language.rawValue).png"))
            try render(NotificationsSettingsView(preferences: preferences, notifier: LimitNotifier(defaults: saved), enabledProviders: [.codex, .claudeCode]).appLanguage(language),
                       width: 650, height: 520, to: destination.appending(path: "notifications-\(language.rawValue).png"))
        }
    }

    private func render(_ view: some View, width: CGFloat, height: CGFloat, to url: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(image.count > 1000)
        try image.write(to: url)
    }
}
