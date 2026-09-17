import Foundation

/// One model's local activity today.
///
/// This is activity, not quota. Account limits such as a 5-hour window
/// belong to the account, so a model row never carries a percentage or a
/// limit unless a provider reports one per model — and none does today.
struct ModelActivity: Sendable, Equatable, Identifiable {
    /// The identifier as the tool recorded it, e.g. "claude-fable-5-1".
    /// Kept separate from the display name, which is derived from it.
    var modelID: String
    /// Input-side tokens, including cache reads and writes, when the tool records them.
    var inputTokens: Int64?
    var outputTokens: Int64?
    var totalTokens: Int64
    var requests: Int64
    /// False when the tool reports tokens per model but not how many
    /// requests went to each, so the row shows no count rather than a 0.
    var isRequestCountKnown = true
    var lastUsedAt: Date?
    /// What this model's tokens would have cost at list prices, in USD.
    /// `nil` when the model has no published price, or the tool recorded no
    /// token split to price — a number is never guessed.
    var estimatedCost: Decimal?

    var id: String { modelID }

    /// A short, readable name. Unknown identifiers still get one.
    var displayName: String { ModelNameFormatter.shortName(for: modelID) }
}

extension [ModelActivity] {
    /// Most active first: by tokens, then requests, then name for a stable order.
    func sortedByActivity() -> [ModelActivity] {
        sorted {
            if $0.totalTokens != $1.totalTokens { return $0.totalTokens > $1.totalTokens }
            if $0.requests != $1.requests { return $0.requests > $1.requests }
            return $0.modelID < $1.modelID
        }
    }
}
