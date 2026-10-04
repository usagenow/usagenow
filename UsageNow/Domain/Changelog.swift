import Foundation

/// The project's CHANGELOG.md, shipped in the app bundle and read into
/// releases for the What's New window.
struct Changelog: Equatable, Sendable {
    struct Release: Equatable, Sendable, Identifiable {
        let version: String
        var sections: [Section]

        var id: String { version }
    }

    struct Section: Equatable, Sendable, Identifiable {
        /// "Added", "Changed", "Fixed"… or nil for items listed straight
        /// under a version.
        let title: String?
        var items: [String]

        var id: String { title ?? "" }
    }

    var releases: [Release]

    /// The changelog bundled with this build, or nil when it's missing.
    static func bundled(in bundle: Bundle = .main) -> Changelog? {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let changelog = Changelog(markdown: text)
        return changelog.releases.isEmpty ? nil : changelog
    }

    /// Reads `## version`, `### section`, and `- item` lines. An item may
    /// wrap onto indented lines. Anything before the first version — the
    /// title and introduction — is skipped.
    init(markdown: String) {
        var releases: [Release] = []
        var lastItemIsOpen = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("## ") {
                releases.append(Release(version: Self.text(after: "## ", in: line), sections: []))
                lastItemIsOpen = false
            } else if line.hasPrefix("### ") {
                guard !releases.isEmpty else { continue }
                releases[releases.count - 1].sections.append(
                    Section(title: Self.text(after: "### ", in: line), items: [])
                )
                lastItemIsOpen = false
            } else if line.hasPrefix("- ") {
                guard !releases.isEmpty else { continue }
                let item = Self.text(after: "- ", in: line)
                if releases[releases.count - 1].sections.isEmpty {
                    releases[releases.count - 1].sections.append(Section(title: nil, items: []))
                }
                let last = releases[releases.count - 1].sections.count - 1
                releases[releases.count - 1].sections[last].items.append(item)
                lastItemIsOpen = true
            } else if line.isEmpty {
                lastItemIsOpen = false
            } else if lastItemIsOpen, rawLine.first?.isWhitespace == true {
                let section = releases[releases.count - 1].sections.count - 1
                let items = releases[releases.count - 1].sections[section].items
                releases[releases.count - 1].sections[section].items[items.count - 1] += " " + line
            }
        }

        self.releases = releases.filter { release in
            release.sections.contains { !$0.items.isEmpty }
        }
    }

    private static func text(after prefix: String, in line: String) -> String {
        String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
