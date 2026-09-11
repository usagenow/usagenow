/// Activity observed in the tool's local session records for the current day.
///
/// This is local activity, not quota: it doesn't necessarily match
/// subscription billing, quota consumption, or provider-side usage.
/// Token counts include cached input as recorded by the tool.
/// `nil` means the provider can't observe that value, not zero.
struct LocalActivity: Sendable, Equatable {
    var tokensToday: Int64?
    /// Model responses recorded today.
    var requestsToday: Int64?

    static let unknown = LocalActivity()
}
