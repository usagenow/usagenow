import Foundation

/// The length of a rate-limit window.
///
/// Providers decide which windows exist, and that changes over time and
/// between plans. A snapshot may report any number of windows; nothing
/// assumes a 5-hour or weekly window is present.
enum UsageWindowKind: Sendable, Hashable {
    case fiveHour
    case weekly
    /// A window of another length reported by an official source.
    case custom(minutes: Int)

    /// Maps a window length to a known kind. Unknown lengths stay custom.
    init(durationMinutes: Int) {
        switch durationMinutes {
        case 300: self = .fiveHour
        case 10_080: self = .weekly
        default: self = .custom(minutes: durationMinutes)
        }
    }

    var durationMinutes: Int {
        switch self {
        case .fiveHour: 300
        case .weekly: 10_080
        case .custom(let minutes): minutes
        }
    }
}

/// Quota usage within one rate-limit window.
struct UsageWindow: Sendable, Equatable, Identifiable {
    let kind: UsageWindowKind
    /// Narrows the window to part of the usage, such as one model family
    /// ("Opus"). Comes from the provider; not localized.
    var scope: String? = nil
    /// `nil` when the provider can't determine usage for this window.
    var usage: UsagePercentage?
    /// When the window resets, or `nil` if unknown.
    var resetsAt: Date?

    var id: String { "\(kind.durationMinutes)|\(scope ?? "")" }
}

extension [UsageWindow] {
    /// Shortest windows first, then unscoped before scoped.
    func sortedForDisplay() -> [UsageWindow] {
        sorted {
            if $0.kind.durationMinutes != $1.kind.durationMinutes {
                return $0.kind.durationMinutes < $1.kind.durationMinutes
            }
            return ($0.scope ?? "") < ($1.scope ?? "")
        }
    }
}
