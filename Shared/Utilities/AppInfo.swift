import Foundation

enum AppInfo {
    static let name = "UsageNow"
    static let tagline: LocalizedStringResource = "See what’s left. Keep building."
    static let website = URL(string: "https://usagenow.com")!
    static let x = URL(string: "https://x.com/UsageNow")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
