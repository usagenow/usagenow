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

    /// Predicted changes are entries in the existing timeline, so they
    /// don't need another extension launch just to expire a limit. Keep a
    /// day's events ready in case macOS postpones the next reload.
    static func entryDates(after date: Date, snapshot: WidgetSnapshot?) -> [Date] {
        let horizon = date.addingTimeInterval(24 * 60 * 60)
        var dates: Set<Date> = [date]
        if let snapshot {
            let readings = [snapshot.generatedAt] + snapshot.providers.compactMap(\.updatedAt)
            let staleDates = readings.map { $0.addingTimeInterval(WidgetSnapshot.staleThreshold + 1) }
            let resetDates = snapshot.providers.flatMap { $0.windows.compactMap(\.resetsAt) }
            // Long windows switch from a calendar date to a live timer.
            let countdownDates = resetDates.map { $0.addingTimeInterval(-24 * 60 * 60 + 1) }
            for event in staleDates + resetDates + countdownDates where event > date && event <= horizon {
                dates.insert(event)
            }
        }
        return dates.sorted()
    }

    /// Just after the next reset, or the idle interval — whichever is sooner.
    static func next(after date: Date, snapshot: WidgetSnapshot?) -> Date {
        let idle = date.addingTimeInterval(idleInterval)
        guard let reset = snapshot?.nextReset(after: date)?.resetsAt else { return idle }
        let afterReset = reset.addingTimeInterval(minimumInterval)
        return max(date.addingTimeInterval(minimumInterval), min(idle, afterReset))
    }
}
