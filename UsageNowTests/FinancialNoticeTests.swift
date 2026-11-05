import Foundation
import Testing
@testable import UsageNow

struct FinancialNoticeTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
    private func snapshot(balance: Decimal? = 4, spend: Decimal? = nil, date: Date? = nil) -> ProviderSnapshot {
        ProviderSnapshot(provider: .openrouter, status: .available,
            balance: AccountBalance(currency: "USD", remaining: balance, spentToday: spend,
                spentThisMonth: spend, spendingTimeZoneID: "UTC"), updatedAt: date ?? now)
    }

    @Test func balanceWarnsOnceAndTopUpRearmsItWithoutChangingTheBudget() {
        let rule = FinancialPolicy.Rule(currency: "USD", balanceBelow: 5)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(), rule: rule, memory: &memory, now: now, quiet: false).map(\.kind) == [.balance])
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(balance: 2), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(balance: 50), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(balance: 3), rule: rule, memory: &memory, now: now, quiet: false).count == 1)
    }

    @Test func budgetsWarnAt80Then100AndDoNotRepeatOnCounterCorrections() {
        let rule = FinancialPolicy.Rule(currency: "USD", dailyBudget: 10, monthlyBudget: 10)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 7), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 8), rule: rule, memory: &memory, now: now, quiet: false).map(\.kind) == [.daily, .monthly])
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 10), rule: rule, memory: &memory, now: now, quiet: false).count == 2)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 2), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 12), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
    }

    @Test func utcDailyRolloverDoesNotResetMonthlyNotification() {
        let rule = FinancialPolicy.Rule(currency: "USD", dailyBudget: 10, monthlyBudget: 10)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        _ = FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 11), rule: rule, memory: &memory, now: now, quiet: false)
        let tomorrow = now.addingTimeInterval(86400)
        let result = FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 12, date: tomorrow), rule: rule, memory: &memory, now: tomorrow, quiet: false)
        #expect(result.map(\.kind) == [.daily])
        let nextMonth = ISO8601DateFormatter().date(from: "2026-12-01T00:01:00Z")!
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 12, date: nextMonth), rule: rule, memory: &memory, now: nextMonth, quiet: false).count == 2)
    }

    @Test func quietHoursConsumeTheCrossingInsteadOfCreatingAMorningBacklog() {
        let rule = FinancialPolicy.Rule(currency: "USD", balanceBelow: 5, dailyBudget: 10)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 8), rule: rule, memory: &memory, now: now, quiet: true).isEmpty)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 9), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 11), rule: rule, memory: &memory, now: now, quiet: false).map(\.kind) == [.daily])
    }

    @Test func staleFutureMissingAndDifferentCurrencyReadingsCannotWarn() {
        let rule = FinancialPolicy.Rule(currency: "EUR", balanceBelow: 5, dailyBudget: 10)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(balance: 0, spend: 20), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
        let usd = FinancialPolicy.Rule(currency: "USD", balanceBelow: 5, dailyBudget: 10)
        for date in [now.addingTimeInterval(-601), now.addingTimeInterval(10)] {
            #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 20, date: date), rule: usd, memory: &memory, now: now, quiet: false).isEmpty)
        }
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(balance: nil), rule: usd, memory: &memory, now: now, quiet: false).isEmpty)
    }

    @Test func creditsAndCharactersAreIndependentOfCurrencyAndMoneyBudgets() {
        let rule = FinancialPolicy.Rule(creditsBelow: 100, charactersBelow: 10000, dailyBudget: 1)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        var reading = ProviderSnapshot(provider: .elevenlabs, status: .available,
            activity: LocalActivity(estimatedCostToday: 999), updatedAt: now)
        reading.totals = [.init(kind: .creditsRemaining, value: 50), .init(kind: .charactersRemaining, value: 9000)]
        #expect(FinancialNoticePlanner.evaluate(snapshot: reading, rule: rule, memory: &memory, now: now, quiet: false).map(\.kind) == [.credits, .characters])
    }

    @Test func undocumentedPeriodAndPreviousUtcDayNeverTriggerBudgets() {
        let rule = FinancialPolicy.Rule(currency: "USD", dailyBudget: 10)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        var reading = snapshot(spend: 20)
        reading.balance?.spendingTimeZoneID = nil
        #expect(FinancialNoticePlanner.evaluate(snapshot: reading, rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
        let midnight = ISO8601DateFormatter().date(from: "2026-11-05T00:00:30Z")!
        reading = snapshot(spend: 20, date: midnight.addingTimeInterval(-60))
        #expect(FinancialNoticePlanner.evaluate(snapshot: reading, rule: rule, memory: &memory, now: midnight, quiet: false).isEmpty)
    }

    @Test func invalidBudgetDoesNotDivideByZero() {
        let rule = FinancialPolicy.Rule(currency: "USD", dailyBudget: 0, monthlyBudget: -1)
        var memory = FinancialNoticePlanner.Memory(rule: rule)
        #expect(FinancialNoticePlanner.evaluate(snapshot: snapshot(spend: 200), rule: rule, memory: &memory, now: now, quiet: false).isEmpty)
    }
}

@MainActor
struct FinancialNotifierPersistenceTests {
    private final class Recorder: LimitNoticeDelivering {
        var delivered: [String] = []
        func deliver(identifier: String, title: String, body: String, at date: Date?) { delivered.append(identifier) }
        func cancel(identifiers: [String]) {}
        func cancelAll() {}
    }

    @Test func relaunchDoesNotRepeatAndFailedRefreshCannotTriggerANewAlert() {
        let defaults = UserDefaults(suiteName: "Financial.\(UUID())")!
        let delivery = Recorder()
        let now = TestDates.noon
        let source = SourceKey(provider: .openrouter)
        let policy = FinancialPolicy(rules: [source.description: .init(currency: "USD", balanceBelow: 5)])
        let snapshot = ProviderSnapshot(provider: .openrouter, status: .available,
            balance: AccountBalance(currency: "USD", remaining: 2), updatedAt: now)
        var state = ProviderState(provider: .openrouter, snapshot: snapshot)
        state.failure = .init(message: "offline", date: now)
        let first = FinancialNotifier(defaults: defaults, delivery: delivery)
        first.update(states: [state], enabledProviders: [.openrouter], enabled: true, policy: policy, quietHours: .init(), now: now)
        #expect(delivery.delivered.isEmpty)
        state.failure = nil
        first.update(states: [state], enabledProviders: [.openrouter], enabled: true, policy: policy, quietHours: .init(), now: now)
        #expect(delivery.delivered.count == 1)
        FinancialNotifier(defaults: defaults, delivery: delivery).update(states: [state], enabledProviders: [.openrouter], enabled: true, policy: policy, quietHours: .init(), now: now)
        #expect(delivery.delivered.count == 1)
    }
}
