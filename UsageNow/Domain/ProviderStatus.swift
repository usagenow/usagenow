/// What a provider reports about its own availability.
///
/// Refresh failures aren't a status: providers throw, and `UsageStore`
/// keeps the last good snapshot alongside the failure.
enum ProviderStatus: Sendable, Equatable {
    /// The tool is installed and signed in. Individual data points may
    /// still be missing; see `ProviderSnapshot.capabilities`.
    case available
    /// The tool is installed but not signed in.
    case notAuthenticated
    /// The tool is present, but its data can't be read right now —
    /// for example permission denied or an unreadable format.
    case unavailable
    /// The tool doesn't appear to be installed on this Mac.
    /// The UI hides the provider entirely.
    case notInstalled
}
