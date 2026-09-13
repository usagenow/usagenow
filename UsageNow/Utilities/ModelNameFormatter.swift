import Foundation

/// Turns model identifiers into readable names without knowing specific
/// models: "claude-fable-5-1" → "Claude Fable 5.1", "gemini-2.5-pro" →
/// "Gemini 2.5 Pro", "gpt-5.6-sol" → "GPT-5.6-sol". Identifiers from an
/// unknown family are shown cleaned up but otherwise as recorded, so a new
/// model never disappears.
enum ModelNameFormatter {
    /// Families whose identifiers follow the "family-name-version" pattern.
    private static let wordFamilies: Set<String> = ["claude", "gemini"]

    static func displayName(for identifier: String) -> String {
        let id = cleaned(identifier)
        let lowercased = id.lowercased()
        if let family = lowercased.split(separator: "-").first.map(String.init), wordFamilies.contains(family) {
            return words(lowercased)
        }
        if lowercased.hasPrefix("gpt-") {
            return "GPT" + id.dropFirst(3)
        }
        return id
    }

    /// The name without its family when the family is obvious from context:
    /// "Claude Fable 5.1" → "Fable 5.1". Kept whole when what follows the
    /// family is only a version ("Claude 3.5 Sonnet", "Gemini 2.5 Pro").
    static func shortName(for identifier: String) -> String {
        let name = displayName(for: identifier)
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              wordFamilies.contains(parts[0].lowercased()),
              parts[1].first?.isLetter == true else { return name }
        return parts[1]
    }

    /// Trims whitespace and API path prefixes such as "models/".
    private static func cleaned(_ identifier: String) -> String {
        var id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = id.lastIndex(of: "/") {
            id = String(id[id.index(after: slash)...])
        }
        return id.isEmpty ? identifier : id
    }

    private static func words(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        // Drop a trailing date stamp such as "20250929".
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        // Join consecutive version numbers: ["4", "1"] → "4.1".
        var words: [String] = []
        for part in parts {
            if part.allSatisfy(\.isNumber), let previous = words.last, previous.first?.isNumber == true {
                words[words.count - 1] = previous + "." + part
            } else {
                words.append(part.first?.isNumber == true ? part : part.capitalized)
            }
        }
        return words.joined(separator: " ")
    }
}
