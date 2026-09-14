/// Why a provider can't report quota right now, in terms every provider
/// can express. Providers keep their own, more detailed diagnosis for logs;
/// this is what the UI turns into a short explanation.
///
/// `nil` on a snapshot means there's nothing to explain: either quota is
/// there, or the provider simply doesn't offer it.
enum QuotaUnavailableReason: String, Sendable, Equatable, Codable {
    /// The saved sign-in is missing, expired, or was rejected.
    case signInExpired
    /// UsageNow wasn't allowed to read the sign-in.
    case permissionDenied
    /// The provider's usage service didn't answer, or answered in a way
    /// UsageNow doesn't understand.
    case temporarilyUnavailable
    /// Limits come from the provider's own tool, and it isn't running now.
    case toolNotRunning
}
