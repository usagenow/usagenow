import Foundation
import Testing

@testable import UsageNow

struct UsageAmountStyleTests {
    private let usage = UsagePercentage(percent: 42)!

    @Test func leftAndUsedAddUpToAHundred() {
        #expect(UsageAmountStyle.remaining.displayValue(usage) == 58)
        #expect(UsageAmountStyle.used.displayValue(usage) == 42)
        #expect(UsageAmountStyle.remaining.barFraction(usage) == 1 - 0.42)
        #expect(UsageAmountStyle.used.barFraction(usage) == 0.42)
    }

    /// Nearly exhausted is never shown as exhausted, either way round.
    @Test func exhaustedOnlyWhenItIs() throws {
        let almost = try #require(UsagePercentage(percent: 99.7))
        #expect(UsageAmountStyle.used.displayValue(almost) == 99)
        #expect(UsageAmountStyle.remaining.displayValue(almost) == 1)
        let done = try #require(UsagePercentage(percent: 100))
        #expect(UsageAmountStyle.used.displayValue(done) == 100)
        #expect(UsageAmountStyle.remaining.displayValue(done) == 0)
    }

    @Test func describesItselfForVoiceOver() {
        let locale = Locale(identifier: "en_US")
        #expect(UsageFormatter.percent(usage, locale: locale) == "42%")
        #expect(UsageAmountStyle.used.accessibilityDescription(usage).hasSuffix("used"))
        #expect(UsageAmountStyle.remaining.accessibilityDescription(usage).hasSuffix("left"))
    }

    @MainActor
    @Test func thePreferencePersistsAndDefaultsToLeft() {
        let defaults = UserDefaults(suiteName: "style-\(UUID())")!
        #expect(AppPreferences(defaults: defaults).usageAmountStyle == .remaining)
        AppPreferences(defaults: defaults).usageAmountStyle = .used
        #expect(AppPreferences(defaults: defaults).usageAmountStyle == .used)
    }
}
