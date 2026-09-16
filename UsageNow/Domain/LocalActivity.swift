import Foundation

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
    /// What today's tokens would have cost at published API prices, in USD.
    ///
    /// An estimate, and never a bill: a subscription doesn't charge per token,
    /// prices change, and a model UsageNow has no price for isn't counted.
    /// `nil` when nothing could be priced.
    var estimatedCostToday: Decimal?
    /// False when some of today's activity is missing from the estimate, so
    /// the UI can say the number is a floor rather than the whole picture.
    var isCostComplete = true

    static let unknown = LocalActivity()
}
