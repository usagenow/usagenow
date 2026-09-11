import Foundation

/// UI-facing state for one provider: its latest good snapshot plus refresh status.
struct ProviderState: Sendable, Equatable, Identifiable {
    let provider: ProviderID
    /// The most recent successful snapshot. Kept when a later refresh fails.
    var snapshot: ProviderSnapshot?
    /// Set when the latest refresh attempt failed.
    var failure: RefreshFailure?
    var isRefreshing = false

    var id: ProviderID { provider }

    /// Whether the popover should show this provider at all.
    var isVisible: Bool {
        if let snapshot { return snapshot.status != .notInstalled }
        return failure != nil
    }
}

struct RefreshFailure: Sendable, Equatable {
    /// Technical detail, shown as a tooltip.
    var message: String
    var date: Date
}
