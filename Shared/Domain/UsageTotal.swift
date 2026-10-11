import Foundation

/// An absolute counter reported by a service, not today's local activity.
/// Closed labels and numeric values are safe to copy into widget snapshots.
struct UsageTotal: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case creditsUsed, creditsRemaining, charactersUsed

        var title: LocalizedStringResource {
            switch self {
            case .creditsUsed: "Credits used"
            case .creditsRemaining: "Credits remaining"
            case .charactersUsed: "Characters used"
            }
        }
    }

    var kind: Kind
    var value: Decimal
    var id: Kind { kind }
}
