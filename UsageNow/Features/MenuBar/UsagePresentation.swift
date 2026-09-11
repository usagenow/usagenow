import SwiftUI

extension UsageLevel {
    /// Subtle semantic tint. Normal and elevated usage keep the system accent color.
    var tint: Color {
        switch self {
        case .normal, .elevated: .accentColor
        case .high: .orange
        case .critical: .red
        }
    }

    /// Shape cue for levels that need attention, so state never relies on color alone.
    var symbolName: String? {
        switch self {
        case .normal, .elevated: nil
        case .high: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityDescription: String? {
        switch self {
        case .normal, .elevated: nil
        case .high: String(localized: "High usage")
        case .critical: String(localized: "Nearly exhausted")
        }
    }
}

extension UsageWindowKind {
    /// "5-hour", "Weekly", or a label derived from the window length.
    var title: String {
        switch self {
        case .fiveHour:
            String(localized: "5-hour")
        case .weekly:
            String(localized: "Weekly")
        case .custom(let minutes) where minutes % (24 * 60) == 0:
            String(localized: "\(minutes / (24 * 60))-day", comment: "Usage window length, e.g. 30-day")
        case .custom(let minutes) where minutes % 60 == 0:
            String(localized: "\(minutes / 60)-hour", comment: "Usage window length, e.g. 12-hour")
        case .custom(let minutes):
            String(localized: "\(minutes)-minute", comment: "Usage window length, e.g. 90-minute")
        }
    }
}

extension UsageWindow {
    var accessibilityTitle: String {
        if let scope {
            return String(localized: "\(kind.title) \(scope) usage", comment: "e.g. Weekly Opus usage")
        }
        return String(localized: "\(kind.title) usage", comment: "e.g. Weekly usage")
    }
}
