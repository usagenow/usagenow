import Foundation

/// Display formatting for usage numbers. Domain models keep raw values;
/// only views format them.
enum UsageFormatter {
    /// Shown for unknown values. Never a fake number.
    static let placeholder = "—"

    /// Compact token counts: 12,400 → "12.4K", 1,280,000 → "1.28M".
    static func tokens(_ value: Int64, locale: Locale = AppLocale.current) -> String {
        max(0, value).formatted(
            .number
                .notation(.compactName)
                .precision(.significantDigits(1...3))
                .locale(locale)
        )
    }

    /// Whole-number counts with grouping: 1204 → "1,204".
    static func count(_ value: Int64, locale: Locale = AppLocale.current) -> String {
        max(0, value).formatted(.number.locale(locale))
    }

    /// Credits as the tool meters them: 2.4669 → "2.47", 12 → "12".
    static func credits(_ value: Decimal, locale: Locale = AppLocale.current) -> String {
        max(0, value).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// An estimated amount in US dollars, the currency providers publish
    /// prices in: 4.2 → "$4.20", 0.038 → "$0.004", 0 → "$0.00".
    ///
    /// Small amounts keep three decimals rather than rounding to "$0.00",
    /// which would read as "nothing" when it isn't.
    static func money(_ value: Decimal, currency: String = "USD", locale: Locale = AppLocale.current) -> String {
        let amount = max(0, value)
        let decimals = amount > 0 && amount < Decimal(string: "0.01")! ? 3 : 2
        return amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(decimals))
                .locale(locale)
        )
    }

    /// Percent used: "42%", using the display rounding rules of `UsagePercentage`.
    static func percent(_ usage: UsagePercentage, locale: Locale = AppLocale.current) -> String {
        percentString(usage.displayValue, locale: locale)
    }

    /// Percent left: "58%" when 42% is used. This is what the UI shows.
    static func remainingPercent(_ usage: UsagePercentage, locale: Locale = AppLocale.current) -> String {
        percentString(usage.remainingDisplayValue, locale: locale)
    }

    private static func percentString(_ value: Int, locale: Locale) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
