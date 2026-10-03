import Foundation

/// Which form a word takes after a whole number, for the languages UsageNow
/// is translated into.
///
/// String catalogs pluralize only strings that contain the number. Where
/// the number is set apart from its word — bold, with the word in gray —
/// the word is a string of its own, one per form, and this picks the form.
enum PluralCategory: Sendable, Equatable {
    case one
    case few
    case many
    case other

    /// CLDR's rules for whole numbers.
    static func of(_ count: Int64, language: String? = AppLocale.current.language.languageCode?.identifier) -> PluralCategory {
        let n = abs(count)
        switch language {
        case "ru":
            if n % 10 == 1, n % 100 != 11 { return .one }
            if (2...4).contains(n % 10), !(12...14).contains(n % 100) { return .few }
            return .many
        case "fr":
            return n <= 1 ? .one : .other
        default:
            return n == 1 ? .one : .other
        }
    }
}

extension UsageFormatter {
    /// "request" or "requests" — the word alone, in the form `count` takes.
    static func requestsUnit(_ count: Int64) -> String {
        switch PluralCategory.of(count) {
        case .one: String(localized: "requests.one", defaultValue: "request", comment: "Follows a request count of one, e.g. 1 request")
        case .few: String(localized: "requests.few", defaultValue: "requests", comment: "Follows a request count, e.g. 3 requests (Russian: 2–4, 22–24…)")
        case .many: String(localized: "requests.many", defaultValue: "requests", comment: "Follows a request count, e.g. 5 requests (Russian: 5–20, 25–30…)")
        case .other: String(localized: "requests.other", defaultValue: "requests", comment: "Follows a request count, e.g. 12 requests")
        }
    }
}
