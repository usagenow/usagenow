import Foundation

/// The language UsageNow shows itself in. `system` follows macOS; the
/// others match what **System Settings › General › Language & Region ›
/// Applications** sets for UsageNow alone.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case de
    case en
    case es
    case fr
    case ru

    var id: String { rawValue }

    /// The language code, or `nil` to follow macOS.
    var code: String? { self == .system ? nil : rawValue }

    /// "Deutsch", "Español", "Русский": each language in its own name, so
    /// it can be found from any of the others. `nil` for `system`.
    var nativeName: String? {
        guard let code else { return nil }
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale)
    }

    /// The language a stored `AppleLanguages` list starts with, if it's one
    /// UsageNow speaks.
    init(preferredLanguages: [String]?) {
        let code = preferredLanguages?.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        self = Self.allCases.first { $0.code != nil && $0.code == code } ?? .system
    }

    /// The locale to render in, or `nil` to follow macOS.
    var locale: Locale? { code.map(Locale.init(identifier:)) }
}
