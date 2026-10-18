import Foundation
import WidgetKit

/// Reads the shared snapshot and renders it.
///
/// It never refreshes providers itself: no files, keychain, processes, or
/// network. See `WidgetRefreshSchedule` for redraw timing.
struct UsageNowTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetSelectionIntent
    var store: WidgetSnapshotStore? = WidgetSnapshotStore.shared()
    var now: @Sendable () -> Date = { .now }

    func placeholder(in context: Context) -> UsageNowWidgetEntry {
        UsageNowWidgetEntry(date: now(), snapshot: store?.read())
    }

    func snapshot(for configuration: WidgetSelectionIntent, in context: Context) async -> UsageNowWidgetEntry {
        let date = now()
        let snapshot = store?.read()?.selecting(configuration.sources?.map(\.id) ?? [])
        Self.adoptLanguage(of: snapshot)
        return UsageNowWidgetEntry(date: date, snapshot: snapshot?.asOf(date))
    }

    func timeline(for configuration: WidgetSelectionIntent, in context: Context) async -> Timeline<UsageNowWidgetEntry> {
        let date = now()
        let snapshot = store?.read()?.selecting(configuration.sources?.map(\.id) ?? [])
        Self.adoptLanguage(of: snapshot)
        let entries = WidgetRefreshSchedule.entryDates(after: date, snapshot: snapshot).map { date in
            UsageNowWidgetEntry(date: date, snapshot: snapshot?.asOf(date))
        }
        return Timeline(entries: entries, policy: .after(WidgetRefreshSchedule.next(after: date, snapshot: snapshot)))
    }

    /// The view follows the app's language at once through its locale;
    /// text built outside views follows the widget's own language list,
    /// which macOS reads when the widget next starts. Keep it matching.
    private static func adoptLanguage(of snapshot: WidgetSnapshot?) {
        guard let snapshot else { return }
        let defaults = UserDefaults.standard
        if let code = snapshot.language {
            if (defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first != code {
                defaults.set([code], forKey: "AppleLanguages")
            }
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}
