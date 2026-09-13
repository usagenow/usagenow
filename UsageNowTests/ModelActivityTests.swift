import Foundation
import Testing
@testable import UsageNow

/// Model activity is generic: these fixtures use real-looking identifiers,
/// but nothing in the code knows any of them.
struct ModelActivityTests {
    private let noon = TestDates.noon
    private var since: Date { TestDates.utc.startOfDay(for: noon) }

    private func record(
        _ key: String,
        model: String?,
        tokens: Int64 = 100,
        input: Int64? = nil,
        output: Int64? = nil,
        at offset: TimeInterval = -60
    ) -> ActivityRecord {
        ActivityRecord(key: key, timestamp: noon.addingTimeInterval(offset), tokens: tokens, model: model, inputTokens: input, outputTokens: output)
    }

    // MARK: Aggregation

    @Test func noRecordsMeansNoModels() {
        let summary = ActivitySummary(records: [], since: since)
        #expect(summary.models.isEmpty)
        #expect(summary.tokens == 0)
    }

    @Test func oneModel() {
        let summary = ActivitySummary(records: [record("a", model: "claude-fable-5-1", tokens: 500)], since: since)
        #expect(summary.models.count == 1)
        #expect(summary.models.first?.displayName == "Fable 5.1")
        #expect(summary.models.first?.totalTokens == 500)
        #expect(summary.models.first?.requests == 1)
    }

    @Test func aggregatesResponsesFromTheSameModel() {
        let summary = ActivitySummary(records: [
            record("a", model: "claude-fable-5-1", tokens: 700, input: 600, output: 100, at: -300),
            record("b", model: "claude-fable-5-1", tokens: 300, input: 250, output: 50, at: -60),
        ], since: since)

        let fable = summary.models.first
        #expect(summary.models.count == 1)
        #expect(fable?.totalTokens == 1_000)
        #expect(fable?.inputTokens == 850)
        #expect(fable?.outputTokens == 150)
        #expect(fable?.requests == 2)
        #expect(fable?.lastUsedAt == noon.addingTimeInterval(-60))
    }

    @Test func multipleModelsSortedByActivity() {
        let summary = ActivitySummary(records: [
            record("a", model: "claude-sonnet-5", tokens: 4_700),
            record("b", model: "claude-fable-5-1", tokens: 72_400),
            record("c", model: "claude-opus-5", tokens: 18_100),
            record("d", model: "claude-fable-5-1", tokens: 100),
        ], since: since)

        #expect(summary.models.map(\.modelID) == ["claude-fable-5-1", "claude-opus-5", "claude-sonnet-5"])
        #expect(summary.models.map(\.displayName) == ["Fable 5.1", "Opus 5", "Sonnet 5"])
        #expect(summary.tokens == 95_300, "Totals still include every model")
        #expect(summary.requests == 4)
    }

    @Test func tiesAreBrokenByRequestsThenName() {
        let summary = ActivitySummary(records: [
            record("a", model: "model-b", tokens: 100),
            record("b", model: "model-a", tokens: 100),
            record("c", model: "model-c", tokens: 50),
            record("d", model: "model-c", tokens: 50),
        ], since: since)
        #expect(summary.models.map(\.modelID) == ["model-c", "model-a", "model-b"])
    }

    @Test func anUnknownFutureModelStillAppears() {
        let summary = ActivitySummary(records: [record("a", model: "claude-nebula-7-2-20271101")], since: since)
        #expect(summary.models.first?.modelID == "claude-nebula-7-2-20271101")
        #expect(summary.models.first?.displayName == "Nebula 7.2")
    }

    @Test func aModelWithZeroTokensStillCountsItsRequests() {
        let summary = ActivitySummary(records: [record("a", model: "claude-opus-5", tokens: 0)], since: since)
        #expect(summary.models.first?.totalTokens == 0)
        #expect(summary.models.first?.requests == 1)
    }

    @Test func recordsWithoutAModelCountTowardTotalsOnly() {
        let summary = ActivitySummary(records: [
            record("a", model: nil, tokens: 300),
            record("b", model: "  ", tokens: 200),
            record("c", model: "claude-opus-5", tokens: 100),
        ], since: since)
        #expect(summary.tokens == 600)
        #expect(summary.requests == 3)
        #expect(summary.models.map(\.modelID) == ["claude-opus-5"])
    }

    @Test func duplicateResponsesAreCountedOnce() {
        let summary = ActivitySummary(records: [
            record("same", model: "claude-opus-5", tokens: 100),
            record("same", model: "claude-opus-5", tokens: 100),
        ], since: since)
        #expect(summary.models.first?.requests == 1)
        #expect(summary.models.first?.totalTokens == 100)
    }

    @Test func recordsBeforeTheDayAreIgnored() {
        let summary = ActivitySummary(records: [record("old", model: "claude-opus-5", at: -13 * 3_600)], since: since)
        #expect(summary.models.isEmpty)
    }

    @Test func splitIsUnknownWhenNoRecordReportsIt() {
        let summary = ActivitySummary(records: [record("a", model: "gpt-example", tokens: 100)], since: since)
        #expect(summary.models.first?.inputTokens == nil)
        #expect(summary.models.first?.outputTokens == nil)
    }

    @Test func negativeCountsNeverReduceTotals() {
        let summary = ActivitySummary(records: [record("a", model: "m", tokens: -50, input: -10, output: -5)], since: since)
        #expect(summary.tokens == 0)
        #expect(summary.models.first?.totalTokens == 0)
        #expect(summary.models.first?.inputTokens == 0)
    }

    // MARK: Snapshot

    @Test func modelActivityIsAModelCapabilityButNeverQuota() {
        let snapshot = ProviderSnapshot(
            provider: .claudeCode,
            status: .available,
            modelActivity: [ModelActivity(modelID: "claude-fable-5-1", totalTokens: 1, requests: 1)],
            updatedAt: noon
        )
        #expect(snapshot.capabilities.contains(.modelActivity))
        #expect(!snapshot.capabilities.contains(.quota))
        #expect(snapshot.mostCriticalWindow == nil)
    }

    // MARK: Display names

    @Test(arguments: [
        ("claude-fable-5-1", "Claude Fable 5.1", "Fable 5.1"),
        ("claude-fable-5-1-20260801", "Claude Fable 5.1", "Fable 5.1"),
        ("claude-opus-4-1", "Claude Opus 4.1", "Opus 4.1"),
        ("claude-opus-5", "Claude Opus 5", "Opus 5"),
        ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet", "Claude 3.5 Sonnet"),
        ("gemini-2.5-pro", "Gemini 2.5 Pro", "Gemini 2.5 Pro"),
        ("models/gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash Lite Preview", "Gemini 3.1 Flash Lite Preview"),
        ("gpt-5.6-sol", "GPT-5.6-sol", "GPT-5.6-sol"),
        ("  some-new-vendor-model  ", "some-new-vendor-model", "some-new-vendor-model"),
    ])
    func displayNames(identifier: String, display: String, short: String) {
        #expect(ModelNameFormatter.displayName(for: identifier) == display)
        #expect(ModelNameFormatter.shortName(for: identifier) == short)
    }

    @Test func rawIdentifierIsKeptSeparateFromTheDisplayName() {
        let model = ModelActivity(modelID: "claude-fable-5-1-20260801", totalTokens: 1, requests: 1)
        #expect(model.id == "claude-fable-5-1-20260801")
        #expect(model.displayName == "Fable 5.1")
    }

    @Test func popoverListsAtMostThreeModels() {
        #expect(ModelActivityView.maxRows == 3)
    }
}
