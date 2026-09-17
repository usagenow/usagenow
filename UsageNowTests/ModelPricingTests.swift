import Foundation
import Testing

@testable import UsageNow

struct ModelPricingTests {
    /// A small table in the shape `scripts/update-model-prices.py` writes.
    private let table = try! ModelPriceTable(
        data: Data(
            """
            {
              "generated": "2026-09-16",
              "source": "test",
              "unit": "USD per million tokens",
              "models": {
                "claude-opus-5": { "input": "5", "output": "25", "cacheWrite": "6.25", "cacheRead": "0.5" },
                "gpt-5-codex": { "input": "1.25", "output": "10", "cacheRead": "0.125" }
              }
            }
            """.utf8
        )
    )

    /// The worked example from Anthropic's pricing page: 50k input and 15k
    /// output on Opus 5 come to $0.625 in tokens.
    @Test func matchesThePublishedWorkedExample() {
        let tokens = TokenBreakdown(input: 50_000, output: 15_000)
        #expect(table.cost(of: tokens, model: "claude-opus-5") == Decimal(string: "0.625"))
    }

    /// The same example with prompt caching: 10k fresh input, 40k cache reads.
    @Test func pricesCacheReadsBelowInput() {
        let tokens = TokenBreakdown(input: 10_000, output: 15_000, cacheRead: 40_000)
        #expect(table.cost(of: tokens, model: "claude-opus-5") == Decimal(string: "0.445"))
    }

    @Test func pricesCacheWritesAboveInput() {
        let tokens = TokenBreakdown(cacheWrite: 1_000_000)
        #expect(table.cost(of: tokens, model: "claude-opus-5") == Decimal(string: "6.25"))
    }

    /// OpenAI doesn't charge separately for writing a cache, so those tokens
    /// are priced as ordinary input rather than dropped.
    @Test func fallsBackToInputWhenABucketHasNoPrice() {
        let tokens = TokenBreakdown(cacheWrite: 1_000_000)
        #expect(table.cost(of: tokens, model: "gpt-5-codex") == Decimal(string: "1.25"))
    }

    @Test func acceptsADateStampedIdentifier() {
        #expect(table.price(for: "claude-opus-5-20260514")?.input == 5)
    }

    @Test func acceptsAVendorPrefixAndLatestSuffix() {
        #expect(table.price(for: "anthropic/claude-opus-5")?.output == 25)
        #expect(table.price(for: "claude-opus-5-latest")?.output == 25)
    }

    @Test func hasNoEstimateForAModelItDoesNotKnow() {
        #expect(table.price(for: "claude-opus-9") == nil)
        #expect(table.cost(of: TokenBreakdown(input: 1_000), model: "some-new-model") == nil)
    }

    /// A near miss must not borrow a neighbour's price: an unknown model is
    /// shown without a cost rather than with a plausible wrong one.
    @Test func doesNotGuessFromASimilarName() {
        #expect(table.price(for: "claude-opus-5-1") == nil)
        #expect(table.price(for: "claude-opus") == nil)
    }

    @Test func ignoresNegativeCounts() {
        let tokens = TokenBreakdown(input: -5_000, output: 15_000)
        #expect(table.cost(of: tokens, model: "claude-opus-5") == Decimal(string: "0.375"))
    }

    @Test func emptyActivityCostsNothing() {
        #expect(table.cost(of: TokenBreakdown(), model: "claude-opus-5") == 0)
    }

    /// The generated table has to be in the bundle, or every estimate silently
    /// disappears.
    @Test func shipsAPriceTableInTheBundle() throws {
        let bundled = ModelPriceTable.bundled
        #expect(!bundled.isEmpty)
        #expect(bundled.generated != nil)
        let opus = try #require(bundled.price(for: "claude-opus-5"))
        #expect(opus.input == 5)
        #expect(opus.output == 25)
    }

    // MARK: Summaries

    private func record(_ key: String, model: String, _ breakdown: TokenBreakdown?) -> ActivityRecord {
        ActivityRecord(
            key: key,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            tokens: breakdown?.total ?? 1_000,
            model: model,
            breakdown: breakdown
        )
    }

    @Test func summaryTotalsTheCostOfEveryPricedModel() {
        let summary = ActivitySummary(
            records: [
                record("a", model: "claude-opus-5", TokenBreakdown(input: 50_000, output: 15_000)),
                record("b", model: "gpt-5-codex", TokenBreakdown(input: 1_000_000, output: 0)),
            ],
            since: .distantPast,
            prices: table
        )
        #expect(summary.estimatedCost == Decimal(string: "1.875"))
        #expect(summary.isCostComplete)
        #expect(summary.models.first(where: { $0.modelID == "gpt-5-codex" })?.estimatedCost == Decimal(string: "1.25"))
    }

    /// An unpriced model must not quietly vanish from the total: the estimate
    /// is still shown, but marked as covering only part of the activity.
    @Test func summaryFlagsActivityItCouldNotPrice() {
        let summary = ActivitySummary(
            records: [
                record("a", model: "claude-opus-5", TokenBreakdown(input: 50_000, output: 15_000)),
                record("b", model: "some-new-model", TokenBreakdown(input: 900_000, output: 100_000)),
            ],
            since: .distantPast,
            prices: table
        )
        #expect(summary.estimatedCost == Decimal(string: "0.625"))
        #expect(!summary.isCostComplete)
        #expect(summary.models.first(where: { $0.modelID == "some-new-model" })?.estimatedCost == nil)
    }

    /// Codex's older sessions record a total without a split; those tokens
    /// can't be priced, because a cache read and fresh input differ tenfold.
    @Test func summaryCannotPriceRecordsWithoutASplit() {
        let summary = ActivitySummary(
            records: [record("a", model: "claude-opus-5", nil)],
            since: .distantPast,
            prices: table
        )
        #expect(summary.estimatedCost == nil)
        #expect(!summary.isCostComplete)
    }

    /// Nothing to price is not the same as failing to price something: an
    /// empty day shows no estimate and no "partial" warning either.
    @Test func noActivityHasNoEstimateAndNothingMissing() {
        let summary = ActivitySummary(records: [], since: .distantPast, prices: table)
        #expect(summary.estimatedCost == nil)
        #expect(summary.isCostComplete)
    }
}
