import Foundation
import Testing

@testable import UsageNow

struct ChangelogTests {
    @Test func readsVersionsSectionsAndItems() {
        let changelog = Changelog(markdown: """
            # Changelog

            All notable changes to UsageNow.

            ## 0.6.1

            ### Added

            - **Notifications about limits.** Turn them on.
            - A keyboard shortcut.

            ### Fixed

            - A refresh could be ignored.

            ## 0.1.0

            - First milestone.
            """)

        #expect(changelog.releases.map(\.version) == ["0.6.1", "0.1.0"])
        #expect(changelog.releases[0].sections.map(\.title) == ["Added", "Fixed"])
        #expect(changelog.releases[0].sections[0].items == [
            "**Notifications about limits.** Turn them on.",
            "A keyboard shortcut.",
        ])
        #expect(changelog.releases[1].sections == [Changelog.Section(title: nil, items: ["First milestone."])])
    }

    @Test func joinsAnItemWrappedOntoIndentedLines() {
        let changelog = Changelog(markdown: """
            ## 1.0

            - First line
              and its continuation.
            Not part of the item.
            """)

        #expect(changelog.releases[0].sections[0].items == ["First line and its continuation."])
    }

    @Test func skipsAVersionWithNothingListed() {
        let changelog = Changelog(markdown: """
            ## Unreleased

            ### Added

            ## 0.6.1

            - Something.
            """)

        #expect(changelog.releases.map(\.version) == ["0.6.1"])
    }

    /// The window reads the copy in the app bundle; the release must carry
    /// an entry for the version it ships as.
    @Test func bundledChangelogListsThisVersion() throws {
        let changelog = try #require(Changelog.bundled())
        #expect(changelog.releases.first?.version == AppInfo.version)
    }
}
