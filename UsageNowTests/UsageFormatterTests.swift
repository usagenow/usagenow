import Foundation
import Testing
@testable import UsageNow

struct UsageFormatterTests {
    private let locale = Locale(identifier: "en_US")

    @Test(arguments: zip(
        [Int64(0), 999, 1_000, 12_400, 150_000, 999_999, 1_280_000, 12_800_000, 31_200_000, 1_234_567_890],
        ["0", "999", "1K", "12.4K", "150K", "1M", "1.28M", "12.8M", "31.2M", "1.23B"]
    ))
    func compactTokens(value: Int64, expected: String) {
        #expect(UsageFormatter.tokens(value, locale: locale) == expected)
    }

    @Test func negativeTokensClampToZero() {
        #expect(UsageFormatter.tokens(-50, locale: locale) == "0")
    }

    @Test func tokensRespectLocale() {
        #expect(UsageFormatter.tokens(1_280_000, locale: Locale(identifier: "de_DE")).hasPrefix("1,28"))
    }

    @Test func counts() {
        #expect(UsageFormatter.count(47, locale: locale) == "47")
        #expect(UsageFormatter.count(1_204, locale: locale) == "1,204")
    }

    @Test func percentages() throws {
        #expect(UsageFormatter.percent(try #require(UsagePercentage(percent: 74)), locale: locale) == "74%")
        #expect(UsageFormatter.percent(try #require(UsagePercentage(percent: 0)), locale: locale) == "0%")
        #expect(UsageFormatter.percent(try #require(UsagePercentage(percent: 99.7)), locale: locale) == "99%")
    }

    @Test func remainingPercentages() throws {
        #expect(UsageFormatter.remainingPercent(try #require(UsagePercentage(percent: 42)), locale: locale) == "58%")
        #expect(UsageFormatter.remainingPercent(try #require(UsagePercentage(percent: 100)), locale: locale) == "0%")
    }

    @Test func englishUIUsesDecimalPointRegardlessOfRegion() {
        // An English UI in a region that writes "12,8" still shows "12.8M".
        #expect(UsageFormatter.tokens(12_800_000, locale: Locale(identifier: "en")) == "12.8M")
    }
}
