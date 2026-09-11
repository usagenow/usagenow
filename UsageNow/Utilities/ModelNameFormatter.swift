import Foundation

/// Turns model identifiers into readable names: "claude-opus-4-1" →
/// "Claude Opus 4.1", "gpt-5.6-sol" → "GPT-5.6-sol". Unknown identifiers
/// are shown as-is rather than guessed at.
enum ModelNameFormatter {
    static func displayName(for identifier: String) -> String {
        let id = identifier.trimmingCharacters(in: .whitespaces)
        let lowercased = id.lowercased()
        if lowercased.hasPrefix("claude-") {
            return claudeName(lowercased)
        }
        if lowercased.hasPrefix("gpt-") {
            return "GPT" + id.dropFirst(3)
        }
        return id
    }

    private static func claudeName(_ id: String) -> String {
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
                words.append(part.allSatisfy(\.isNumber) ? part : part.capitalized)
            }
        }
        return words.joined(separator: " ")
    }
}
