import Foundation

/// User-chosen, account-scoped alerts. Money always keeps its source currency.
struct FinancialPolicy: Codable, Equatable, Sendable {
    struct Rule: Codable, Equatable, Sendable {
        var currency: String? = nil
        var balanceBelow: Decimal? = nil
        var creditsBelow: Decimal? = nil
        var charactersBelow: Decimal? = nil
        var dailyBudget: Decimal? = nil
        var monthlyBudget: Decimal? = nil
        var isEmpty: Bool { [balanceBelow, creditsBelow, charactersBelow, dailyBudget, monthlyBudget].allSatisfy { $0 == nil } }
    }
    var rules: [String: Rule] = [:]
    func rule(for source: SourceKey) -> Rule { rules[source.description] ?? Rule() }

    static func valid(_ amount: Decimal?) -> Decimal? {
        guard let amount, !amount.isNaN, amount > 0 else { return nil }
        return amount
    }
}

/// Pure alert planner; persistent state is separate from notification delivery.
struct FinancialNoticePlanner {
    struct Memory: Codable, Equatable {
        var rule: FinancialPolicy.Rule
        var lowBalance = false
        var lowCredits = false
        var lowCharacters = false
        var dailyPeriod: Date? = nil
        var monthlyPeriod: Date? = nil
        var dailyLevel = 0
        var monthlyLevel = 0
    }
    enum Kind: String, Codable { case balance, credits, characters, daily, monthly }
    struct Notice: Equatable {
        var kind: Kind
        var amount: Decimal
        var currency: String? = nil
        var budget: Decimal? = nil
    }

    static func evaluate(snapshot: ProviderSnapshot, rule: FinancialPolicy.Rule, memory: inout Memory,
                         now: Date, quiet: Bool) -> [Notice] {
        guard snapshot.status == .available, !snapshot.isStale(at: now), snapshot.dataDate <= now else { return [] }
        if memory.rule != rule { memory = Memory(rule: rule) }
        var notices: [Notice] = []
        func low(_ amount: Decimal?, threshold: Decimal?, active: inout Bool, kind: Kind, currency: String? = nil) {
            guard let amount, !amount.isNaN, let threshold = FinancialPolicy.valid(threshold) else { return }
            if amount > threshold { active = false; return }
            if !active && !quiet { notices.append(Notice(kind: kind, amount: amount, currency: currency)) }
            active = true // Quiet alerts are consumed, never queued until morning.
        }
        if let balance = snapshot.balance, balance.currency == rule.currency {
            low(balance.remaining, threshold: rule.balanceBelow, active: &memory.lowBalance, kind: .balance, currency: balance.currency)
            // Only a provider's documented reporting calendar may identify a
            // new daily/monthly counter. A top-up is never interpreted as spend.
            if let zone = balance.spendingTimeZoneID.flatMap(TimeZone.init(identifier:)) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                let daily = calendar.startOfDay(for: snapshot.dataDate)
                let month = calendar.dateInterval(of: .month, for: snapshot.dataDate)?.start
                if memory.dailyPeriod != daily { memory.dailyPeriod = daily; memory.dailyLevel = 0 }
                if memory.monthlyPeriod != month { memory.monthlyPeriod = month; memory.monthlyLevel = 0 }
                func budget(_ amount: Decimal?, limit: Decimal?, level: inout Int, kind: Kind) {
                    guard let amount, !amount.isNaN, amount >= 0, let limit = FinancialPolicy.valid(limit) else { return }
                    let next = amount >= limit ? 100 : amount >= limit * Decimal(string: "0.8")! ? 80 : 0
                    if next > level {
                        if !quiet { notices.append(Notice(kind: kind, amount: amount, currency: balance.currency, budget: limit)) }
                        level = next
                    }
                }
                if calendar.isDate(snapshot.dataDate, inSameDayAs: now) {
                    budget(balance.spentToday, limit: rule.dailyBudget, level: &memory.dailyLevel, kind: .daily)
                }
                if calendar.dateInterval(of: .month, for: now)?.start == month {
                    budget(balance.spentThisMonth, limit: rule.monthlyBudget, level: &memory.monthlyLevel, kind: .monthly)
                }
            }
        }
        low(snapshot.totals.first { $0.kind == .creditsRemaining }?.value,
            threshold: rule.creditsBelow, active: &memory.lowCredits, kind: .credits)
        low(snapshot.totals.first { $0.kind == .charactersRemaining }?.value,
            threshold: rule.charactersBelow, active: &memory.lowCharacters, kind: .characters)
        return notices
    }
}
