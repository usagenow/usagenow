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
    static let kind = WidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UsageNowTimelineProvider()) { entry in
            let language = AppLanguage(rawValue: entry.snapshot?.language ?? "")
            UsageNowWidgetEntryView(entry: entry)
                .appLanguage(language)
        }
        .configurationDisplayName(Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? AppInfo.name))
        .description(Text("What’s left of your AI coding limits, at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
