import Foundation

/// Formats reset times and data freshness. Inputs are always `Date`s;
/// formatted strings are never stored in domain models.
struct ResetTimeFormatter: Sendable {
    /// Resets closer than this show a countdown instead of a weekday and time.
    static let countdownThreshold: TimeInterval = 24 * 60 * 60

    var calendar: Calendar = .autoupdatingCurrent
    var locale: Locale = AppLocale.current
    var timeZone: TimeZone = .autoupdatingCurrent

    /// "1h 24m", "3h 08m", "38m", "2d 4h".
    ///
    /// Rounds up to the next minute, so a live countdown reads "1m"
    /// until the reset actually happens.
    func countdown(from now: Date, to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        let totalMinutes = seconds > 0 ? Int((seconds / 60).rounded(.up)) : 0
        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes % (24 * 60) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return String(localized: "\(days)d \(hours)h", comment: "Countdown in days and hours, e.g. 2d 4h")
        }
        if hours > 0 {
            let paddedMinutes = minutes.formatted(.number.precision(.integerLength(2)).locale(locale))
            return String(localized: "\(hours)h \(paddedMinutes)m", comment: "Countdown in hours and zero-padded minutes, e.g. 3h 08m")
        }
        return String(localized: "\(minutes)m", comment: "Countdown in minutes, e.g. 38m")
    }

    /// "Mon 09:00": localized weekday, 24-hour time.
    func weekdayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEHHmm")
        return formatter.string(from: date)
    }

    /// "Resets in 1h 24m" within a day, "Resets Mon 09:00" beyond that.
    func resetDescription(for date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return String(localized: "Resetting now")
        }
        if interval < Self.countdownThreshold {
            return String(localized: "Resets in \(countdown(from: now, to: date))")
        }
        return String(localized: "Resets \(weekdayTime(date))")
    }

    /// Spoken form for VoiceOver: "resets in 1 hour, 24 minutes".
    func accessibleResetDescription(for date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0, interval < Self.countdownThreshold else {
            return resetDescription(for: date, now: now)
        }
        let formatter = DateComponentsFormatter()
        var spellingCalendar = calendar
        spellingCalendar.locale = locale
        formatter.calendar = spellingCalendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        let roundedUp = (interval / 60).rounded(.up) * 60
        let spoken = formatter.string(from: roundedUp) ?? countdown(from: now, to: date)
        return String(localized: "Resets in \(spoken)")
    }

    /// "Just now", "2m ago", "3h ago", "2d ago".
    func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return String(localized: "Just now")
        case ..<3600: return String(localized: "\(Int(seconds / 60))m ago")
        case ..<86_400: return String(localized: "\(Int(seconds / 3600))h ago")
        default: return String(localized: "\(Int(seconds / 86_400))d ago")
        }
    }

    /// "Updated just now", "Updated 18m ago".
    func updatedDescription(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 {
            return String(localized: "Updated just now")
        }
        return String(localized: "Updated \(relative(date, now: now))")
    }
}
