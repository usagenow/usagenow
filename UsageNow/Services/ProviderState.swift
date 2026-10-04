import Foundation

/// UI-facing state for one provider: its latest good snapshot plus refresh status.
struct ProviderState: Sendable, Equatable, Identifiable {
    let provider: ProviderID
    /// The added account this row shows; `nil` for the provider's own.
    var account: AccountTag? = nil
    /// The most recent successful snapshot. Kept when a later refresh fails.
    var snapshot: ProviderSnapshot?
    /// Set when the latest refresh attempt failed.
    var failure: RefreshFailure?
    var isRefreshing = false

    var id: SourceKey { SourceKey(provider: provider, account: account?.id) }

    /// "Codex", or "Codex · Work" for an added account.
    var displayName: String { provider.displayName(account: account) }

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
