/// A usage amount normalized to the 0–100 percent range.
///
/// Providers report usage in different shapes (fractions, percentages,
/// used/limit pairs). Normalizing here keeps the UI free of provider details.
struct UsagePercentage: Sendable, Hashable, Comparable, Codable {
    /// Percent used, clamped to `0...100`.
    let value: Double

    /// Returns `nil` for non-finite input.
    init?(percent: Double) {
        guard percent.isFinite else { return nil }
        value = min(max(percent, 0), 100)
    }

    /// Creates a percentage from a `0...1` fraction.
    init?(fraction: Double) {
        self.init(percent: fraction * 100)
    }

    /// Creates a percentage from raw counts. Returns `nil` when the limit is
    /// zero or negative, since usage is unknowable then.
    init?(used: Double, limit: Double) {
        guard limit > 0, used.isFinite, limit.isFinite else { return nil }
        self.init(fraction: used / limit)
    }

    var fraction: Double { value / 100 }

    /// Whole percent for display. Never shows 100 until the limit is
    /// actually reached, so "100%" always means exhausted.
    var displayValue: Int {
        let rounded = Int(value.rounded())
        return rounded == 100 && value < 100 ? 99 : rounded
    }

    /// Whole percent left, consistent with `displayValue`: "0% left" only
    /// once the limit is actually reached.
    var remainingDisplayValue: Int { 100 - displayValue }

    var remainingFraction: Double { 1 - fraction }

    /// Severity based on the displayed value, so the tint always agrees
    /// with the number the user sees.
    var level: UsageLevel { UsageLevel(percent: displayValue) }

    static func < (lhs: UsagePercentage, rhs: UsagePercentage) -> Bool {
        lhs.value < rhs.value
    }

    // Stored as a bare number, and clamped again on the way back in.
    init(from decoder: any Decoder) throws {
        let stored = try decoder.singleValueContainer().decode(Double.self)
        guard let percentage = UsagePercentage(percent: stored) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Usage percentage isn’t a finite number"))
        }
        self = percentage
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
