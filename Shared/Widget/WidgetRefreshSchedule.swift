import Foundation

/// When the widget should redraw.
///
/// Usage values only change when the main app writes a new snapshot and
/// reloads timelines. These refreshes exist so countdowns stay honest,
/// so they stay sparse.
enum WidgetRefreshSchedule {
    /// Used when no reset is near.
    static let idleInterval: TimeInterval = 15 * 60
    /// Never schedule tighter than this, to stay a good WidgetKit citizen.
    static let minimumInterval: TimeInterval = 60

    /// Just after the next reset, or the idle interval — whichever is sooner.
    static func next(after date: Date, snapshot: WidgetSnapshot?) -> Date {
        let idle = date.addingTimeInterval(idleInterval)
        guard let reset = snapshot?.nextReset(after: date)?.resetsAt else { return idle }
        let afterReset = reset.addingTimeInterval(minimumInterval)
        return max(date.addingTimeInterval(minimumInterval), min(idle, afterReset))
    }
}
