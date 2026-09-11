import Foundation

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case manual = 0
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    static let `default` = RefreshInterval.fiveMinutes

    var id: Int { rawValue }

    /// `nil` for manual refresh.
    var duration: Duration? {
        self == .manual ? nil : .seconds(rawValue)
    }

    var title: LocalizedStringResource {
        switch self {
        case .manual: "Manual"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        }
    }
}
