import SwiftUI

/// Every release's changes, read from the CHANGELOG.md bundled with the
/// app, so it works offline and matches the installed version.
struct ChangelogView: View {
    static let onlineURL = URL(string: "https://github.com/usagenow/usagenow/blob/main/CHANGELOG.md")!

    var changelog: Changelog? = .bundled()

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What’s New")
                .font(.title3.weight(.semibold))
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            Divider()

            if let changelog {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(changelog.releases) { release in
                            ReleaseView(release: release)
                        }
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 8) {
                    Text("The list of changes isn’t included in this build.")
                        .foregroundStyle(.secondary)
                    Link(destination: Self.onlineURL) { Text("View on GitHub") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 480)
    }
}

private struct ReleaseView: View {
    let release: Changelog.Release

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Version \(release.version)")
                    .font(.headline)
                if release.version == AppInfo.version {
                    Text("Installed")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Palette.badgeFill, in: .capsule)
                }
            }

            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if let title = section.title {
                        Text(Self.localizedTitle(title))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "•")
                                .foregroundStyle(.secondary)
                            Text(Self.rendered(item))
                                .font(.callout)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// The changelog's text is in English; its standard headings follow
    /// the app's language.
    private static func localizedTitle(_ title: String) -> String {
        switch title {
        case "Added": String(localized: "Added")
        case "Changed": String(localized: "Changed")
        case "Fixed": String(localized: "Fixed")
        case "Removed": String(localized: "Removed")
        default: title
        }
    }

    private static func rendered(_ item: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: item, options: options)) ?? AttributedString(item)
    }
}

#if DEBUG
#Preview {
    ChangelogView(changelog: Changelog(markdown: """
        ## 0.6.1

        ### Added

        - **Notifications about limits.** Turn them on in **Settings › Notifications**.

        ### Fixed

        - A very long line in a session file is skipped without being loaded.
        """))
}
#endif
