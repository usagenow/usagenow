import Foundation

enum AppLocale {
    /// The locale of the language the UI is shown in, so numbers and dates
    /// match the surrounding text: with an English UI, "12.8M" rather than
    /// the region's "12,8M". Once UsageNow is localized, this follows the
    /// language macOS picks for the app.
    static var current: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
