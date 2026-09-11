import Testing
@testable import UsageNow

struct UsageLevelTests {
    @Test(arguments: zip(
        [0, 35, 69, 70, 84, 85, 94, 95, 100],
        [UsageLevel.normal, .normal, .normal, .elevated, .elevated, .high, .high, .critical, .critical]
    ))
    func thresholds(percent: Int, expected: UsageLevel) {
        #expect(UsageLevel(percent: percent) == expected)
    }

    @Test func outOfRangeValuesMapToEnds() {
        #expect(UsageLevel(percent: -5) == .normal)
        #expect(UsageLevel(percent: 180) == .critical)
    }

    @Test func levelFollowsDisplayedValue() {
        // 69.6 displays as 70%, so it must be tinted as elevated.
        #expect(UsagePercentage(percent: 69.6)?.level == .elevated)
        #expect(UsagePercentage(percent: 69.4)?.level == .normal)
        #expect(UsagePercentage(percent: 94.5)?.level == .critical)
    }

    @Test func levelsAreOrdered() {
        #expect(UsageLevel.normal < .elevated)
        #expect(UsageLevel.high < .critical)
    }
}
