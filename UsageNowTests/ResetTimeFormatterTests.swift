import Foundation
import Testing
@testable import UsageNow

struct ResetTimeFormatterTests {
    private let formatter: ResetTimeFormatter = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return ResetTimeFormatter(
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC")!
        )
    }()

    /// Friday, 11 September 2026, 10:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_120_800)

    private func minutes(_ value: Double) -> TimeInterval { value * 60 }

    @Test(arguments: zip(
        [84, 188, 38, 60, 1, 0.5, 83.5, 52 * 60] as [Double],
        ["1h 24m", "3h 08m", "38m", "1h 00m", "1m", "1m", "1h 24m", "2d 4h"]
    ))
    func countdown(minutesAhead: Double, expected: String) {
        let date = now.addingTimeInterval(minutes(minutesAhead))
        #expect(formatter.countdown(from: now, to: date) == expected)
    }

    @Test func countdownForPastDates() {
        #expect(formatter.countdown(from: now, to: now.addingTimeInterval(-30)) == "0m")
    }

    @Test func weekdayTimeUses24HourClock() {
        // Monday 14 September 2026, 09:00 UTC and Tuesday 15 September, 14:30 UTC.
        let monday = Date(timeIntervalSince1970: 1_789_376_400)
        let tuesday = Date(timeIntervalSince1970: 1_789_482_600)
        #expect(formatter.weekdayTime(monday) == "Mon 09:00")
        #expect(formatter.weekdayTime(tuesday) == "Tue 14:30")
    }

    @Test func resetDescriptionUsesCountdownWithinADay() {
        let soon = now.addingTimeInterval(minutes(84))
        #expect(formatter.resetDescription(for: soon, now: now) == "Resets in 1h 24m")
    }

    @Test func resetDescriptionUsesWeekdayBeyondADay() {
        let monday = Date(timeIntervalSince1970: 1_789_376_400)
        #expect(formatter.resetDescription(for: monday, now: now) == "Resets Mon 09:00")
    }

    @Test func resetDescriptionForPassedReset() {
        #expect(formatter.resetDescription(for: now.addingTimeInterval(-1), now: now) == "Resetting now")
    }

    @Test func accessibleDescriptionSpellsOutUnits() {
        let soon = now.addingTimeInterval(minutes(84))
        #expect(formatter.accessibleResetDescription(for: soon, now: now) == "Resets in 1 hour, 24 minutes")
    }

    @Test(arguments: zip(
        [0, 59, 60, 125, 18 * 60, 3 * 3600, 50 * 3600] as [Double],
        ["Just now", "Just now", "1m ago", "2m ago", "18m ago", "3h ago", "2d ago"]
    ))
    func relative(secondsAgo: Double, expected: String) {
        #expect(formatter.relative(now.addingTimeInterval(-secondsAgo), now: now) == expected)
    }

    @Test func updatedDescription() {
        #expect(formatter.updatedDescription(now.addingTimeInterval(-10), now: now) == "Updated just now")
        #expect(formatter.updatedDescription(now.addingTimeInterval(-18 * 60), now: now) == "Updated 18m ago")
    }

    @Test func futureDatesCountAsJustNow() {
        #expect(formatter.relative(now.addingTimeInterval(30), now: now) == "Just now")
    }
}
