import Foundation

enum AppInfo {
    static let name = "UsageNow"
    /// What the app is, in one line. Shown in About and the widget gallery.
    static let summary: LocalizedStringResource = "AI coding usage tracker for macOS"
    /// Brand line, kept for the website and README rather than the UI.
    static let tagline = "See what’s left. Keep building."
    static let website = URL(string: "https://usagenow.com")!
    static let x = URL(string: "https://x.com/UsageNow")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
