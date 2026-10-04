import Foundation
import WidgetKit

/// Reads the shared snapshot and renders it.
///
/// It never refreshes providers itself: no files, keychain, processes, or
/// network. See `WidgetRefreshSchedule` for redraw timing.
struct UsageNowTimelineProvider: TimelineProvider {
    var store: WidgetSnapshotStore? = WidgetSnapshotStore.shared()
    var now: @Sendable () -> Date = { .now }

    func placeholder(in context: Context) -> UsageNowWidgetEntry {
        UsageNowWidgetEntry(date: now(), snapshot: store?.read())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageNowWidgetEntry) -> Void) {
        completion(UsageNowWidgetEntry(date: now(), snapshot: store?.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageNowWidgetEntry>) -> Void) {
        let date = now()
        let snapshot = store?.read()
        Self.adoptLanguage(of: snapshot)
        let entry = UsageNowWidgetEntry(date: date, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(WidgetRefreshSchedule.next(after: date, snapshot: snapshot))))
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
