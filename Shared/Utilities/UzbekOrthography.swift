import Foundation

/// Date formatters still use CLDR's Uzbek spelling. Apply the requested
/// spelling only to date/unit text, never to names, credentials or paths.
enum UzbekOrthography {
    static func dateText(_ value: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "uz" else { return value }
        var result = value
        for mark in ["‘", "’", "ʻ", "ʼ", "'"] {
            for (letter, replacement) in [("O", "Ö"), ("o", "ö"), ("G", "Ğ"), ("g", "ğ")] {
                result = result.replacingOccurrences(of: letter + mark, with: replacement)
            }
        }
        for (letters, replacement) in [("SH", "Ş"), ("Sh", "Ş"), ("sh", "ş"), ("CH", "Ç"), ("Ch", "Ç"), ("ch", "ç")] {
            result = result.replacingOccurrences(of: letters, with: replacement)
        }
        return result
    }
}
