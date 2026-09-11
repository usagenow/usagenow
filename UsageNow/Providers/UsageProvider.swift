import Foundation

/// Why a refresh is happening. Providers that cache expensive or
/// rate-limited sources use it to decide whether to bypass their cache.
enum RefreshTrigger: Sendable, Equatable {
    /// Launch, the refresh interval, or opening the popover.
    case automatic
    /// The user asked for fresh data (Refresh or Retry).
    case manual
}

/// A source of normalized usage data for one tool.
///
/// Implementations translate tool-specific data (local files, official
/// local interfaces, …) into a `ProviderSnapshot`, so the UI never depends
/// on Codex- or Claude-specific details.
protocol UsageProvider: Sendable {
    var id: ProviderID { get }

    /// Returns the provider's current usage. Called off the main actor.
    ///
    /// Report expected conditions through the snapshot's status
    /// (`.notInstalled`, `.notAuthenticated`, `.unavailable`) and missing
    /// data through `nil` fields. Throw only when a refresh attempt failed
    /// and previously loaded data should be kept.
    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot
}

/// Refresh failures. Messages are sanitized: no paths, tokens, or payloads.
enum ProviderError: LocalizedError, Sendable, Equatable {
    case refreshFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .refreshFailed(let reason): reason
        }
    }
}
