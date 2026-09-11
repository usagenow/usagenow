import Testing
@testable import UsageNow

struct UsagePercentageTests {
    @Test func clampsToValidRange() {
        #expect(UsagePercentage(percent: -12)?.value == 0)
        #expect(UsagePercentage(percent: 140)?.value == 100)
        #expect(UsagePercentage(percent: 42.5)?.value == 42.5)
    }

    @Test func rejectsNonFiniteInput() {
        #expect(UsagePercentage(percent: .nan) == nil)
        #expect(UsagePercentage(percent: .infinity) == nil)
        #expect(UsagePercentage(used: .nan, limit: 10) == nil)
    }

    @Test func normalizesFractions() {
        #expect(UsagePercentage(fraction: 0.74)?.displayValue == 74)
        #expect(UsagePercentage(fraction: 1.3)?.value == 100)
    }

    @Test func normalizesUsedAndLimit() {
        #expect(UsagePercentage(used: 1_560_000, limit: 2_000_000)?.displayValue == 78)
        #expect(UsagePercentage(used: 47_600_000, limit: 70_000_000)?.displayValue == 68)
        #expect(UsagePercentage(used: 0, limit: 10)?.value == 0)
    }

    @Test func rejectsMissingLimit() {
        #expect(UsagePercentage(used: 5, limit: 0) == nil)
        #expect(UsagePercentage(used: 5, limit: -1) == nil)
    }

    @Test func roundsToNearestWholePercent() {
        #expect(UsagePercentage(percent: 73.4)?.displayValue == 73)
        #expect(UsagePercentage(percent: 73.5)?.displayValue == 74)
    }

    @Test func showsOneHundredOnlyWhenExhausted() {
        #expect(UsagePercentage(percent: 99.6)?.displayValue == 99)
        #expect(UsagePercentage(percent: 100)?.displayValue == 100)
        #expect(UsagePercentage(used: 11, limit: 10)?.displayValue == 100)
    }

    @Test func remainingMirrorsDisplayedUsage() {
        #expect(UsagePercentage(percent: 42)?.remainingDisplayValue == 58)
        #expect(UsagePercentage(percent: 99.6)?.remainingDisplayValue == 1)
        #expect(UsagePercentage(percent: 100)?.remainingDisplayValue == 0)
        #expect(UsagePercentage(percent: 25)?.remainingFraction == 0.75)
    }

    @Test func fractionMirrorsValue() {
        #expect(UsagePercentage(percent: 25)?.fraction == 0.25)
    }
}
