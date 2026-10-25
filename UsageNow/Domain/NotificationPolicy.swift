import Foundation

/// Local notification choices. Provider rules apply to all of its accounts.
struct NotificationPolicy: Codable, Equatable, Sendable {
    struct Rule: Codable, Equatable, Sendable {
        var enabled = true
        var warning = 20
        var critical = 5
        var resets = true

        var thresholds: [Int] {
            Array(Set([warning, critical].map { min(99, max(1, $0)) })).sorted(by: >)
        }
    }

    var providers: [String: Rule] = [:]
    var quietHoursEnabled = false
    /// Minutes after midnight in the Mac's current time zone.
    var quietStart = 22 * 60
    var quietEnd = 8 * 60

    func rule(for provider: ProviderID) -> Rule { providers[provider.rawValue] ?? Rule() }

    func isQuiet(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard quietHoursEnabled else { return false }
        let start = min(1439, max(0, quietStart))
        let end = min(1439, max(0, quietEnd))
        // Equal times mean no quiet interval, rather than silencing a day.
        guard start != end else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
}
