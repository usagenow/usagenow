import SwiftUI
import WidgetKit

/// The desktop widget.
///
/// It renders the snapshot the main app publishes to the App Group and
/// nothing else: no provider discovery, no `~/.codex` or `~/.claude`
/// access, no keychain, no `codex app-server`, and no network calls. That
/// boundary is enforced by target membership — the provider clients aren't
/// compiled into this target.
@main
struct UsageNowWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageNowWidget()
    }
}

struct UsageNowWidget: Widget {
    static let kind = "UsageNowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UsageNowTimelineProvider()) { entry in
            UsageNowWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: AppInfo.name))
        .description(Text("See what’s left of your Codex and Claude Code limits."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
