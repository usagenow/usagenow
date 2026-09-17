import Foundation

/// The length of a rate-limit window.
///
/// Providers decide which windows exist, and that changes over time and
/// between plans. A snapshot may report any number of windows; nothing
/// assumes a 5-hour or weekly window is present.
enum UsageWindowKind: Sendable, Hashable, Codable {
    case fiveHour
    case weekly
    /// A billing month, which resets on a date rather than after a fixed
    /// length. Distinct from a rolling 30-day window, which stays `custom`.
    case monthly
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
        // Nominal, for ordering against other windows only.
        case .monthly: 43_200
        case .custom(let minutes): minutes
        }
    }

    private static let monthlyToken = "monthly"

    // Stored as a plain length, so the shape survives new cases. A billing
    // month has no fixed length, so it's stored by name instead.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let minutes = try? container.decode(Int.self) {
            self.init(durationMinutes: minutes)
        } else if try container.decode(String.self) == Self.monthlyToken {
            self = .monthly
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown usage window kind"))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if self == .monthly {
            try container.encode(Self.monthlyToken)
        } else {
            try container.encode(durationMinutes)
        }
    }
}

/// Quota usage within one rate-limit window.
struct UsageWindow: Sendable, Equatable, Identifiable, Codable {
    let kind: UsageWindowKind
    /// Narrows the window to part of the usage, such as one model family
    /// ("Opus"). Comes from the provider; not localized.
    var scope: String? = nil
    /// `nil` when the provider can't determine usage for this window.
    var usage: UsagePercentage?
    /// When the window resets, or `nil` if unknown.
    var resetsAt: Date?

    var id: String { "\(kind == .monthly ? "monthly" : String(kind.durationMinutes))|\(scope ?? "")" }
}

extension [UsageWindow] {
    /// The window that matters most right now: the least left, and among
    /// equally tight ones, the one resetting soonest. Windows with unknown
    /// usage are ignored. Shared by the menu bar and the widget so both
    /// agree on what "most relevant" means.
    var mostRelevant: UsageWindow? {
        compactMap { window in window.usage.map { (window, $0) } }
            .min { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                return (left.0.resetsAt ?? .distantFuture) < (right.0.resetsAt ?? .distantFuture)
            }?
            .0
    }

    /// The windows as of `date`, for values read earlier. A window that has
    /// reset since keeps its row, so the display doesn't lose it, but its
    /// usage becomes unknown: nothing says how much of the new window is used.
    func asOf(_ date: Date) -> [UsageWindow] {
        map { window in
            guard let resetsAt = window.resetsAt, resetsAt <= date else { return window }
            var reset = window
            reset.usage = nil
            return reset
        }
    }

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
