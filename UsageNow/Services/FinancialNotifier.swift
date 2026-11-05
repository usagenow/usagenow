import Foundation

@MainActor
final class FinancialNotifier {
    private static let memoryKey = "financialNotifications.memory.v1"
    private let defaults: UserDefaults
    private let delivery: any LimitNoticeDelivering
    private var memory: [String: FinancialNoticePlanner.Memory]

    init(defaults: UserDefaults = .standard, delivery: any LimitNoticeDelivering = SystemNoticeDelivery()) {
        self.defaults = defaults
        self.delivery = delivery
        memory = defaults.data(forKey: Self.memoryKey)
            .flatMap { try? JSONDecoder().decode([String: FinancialNoticePlanner.Memory].self, from: $0) } ?? [:]
    }

    func forget(_ source: SourceKey) {
        memory.removeValue(forKey: source.description)
        delivery.cancel(identifiers: FinancialNoticePlanner.Kind.allValues.map { identifier(source, $0) })
        save()
    }

    func update(states: [ProviderState], enabledProviders: Set<ProviderID>, enabled: Bool,
                policy: FinancialPolicy, quietHours: NotificationPolicy, now: Date = .now) {
        let valid = Set(states.filter { enabledProviders.contains($0.provider) }.map { $0.id.description })
        let before = memory
        memory = memory.filter { valid.contains($0.key) && !(policy.rules[$0.key]?.isEmpty ?? true) }
        guard enabled else {
            for state in states { delivery.cancel(identifiers: FinancialNoticePlanner.Kind.allValues.map { identifier(state.id, $0) }) }
            memory = [:]
            if memory != before { save() }
            return
        }
        for state in states where enabledProviders.contains(state.provider) && state.failure == nil && !state.isRefreshing
            && quietHours.rule(for: state.provider).enabled {
            let rule = policy.rule(for: state.id)
            guard !rule.isEmpty, let snapshot = state.snapshot else { continue }
            var entry = memory[state.id.description] ?? .init(rule: rule)
            let notices = FinancialNoticePlanner.evaluate(snapshot: snapshot, rule: rule, memory: &entry,
                now: now, quiet: quietHours.isQuiet(at: now))
            memory[state.id.description] = entry
            for notice in notices {
                let title: String = switch notice.kind {
                case .balance: String(localized: "Low balance")
                case .credits: String(localized: "Low credits")
                case .characters: String(localized: "Low characters")
                case .daily: String(localized: "Daily budget")
                case .monthly: String(localized: "Monthly budget")
                }
                let amount = notice.currency.map { UsageFormatter.money(notice.amount, currency: $0) } ?? UsageFormatter.credits(notice.amount)
                let body: String
                if let budget = notice.budget, let currency = notice.currency {
                    let cap = UsageFormatter.money(budget, currency: currency)
                    body = String(localized: "\(state.displayName): \(amount) of \(cap)")
                } else { body = String(localized: "\(state.displayName): \(amount) left") }
                delivery.deliver(identifier: identifier(state.id, notice.kind), title: title, body: body, at: nil)
            }
        }
        if memory != before { save() }
    }

    private func identifier(_ source: SourceKey, _ kind: FinancialNoticePlanner.Kind) -> String { "finance.\(source.description).\(kind.rawValue)" }
    private func save() { defaults.set(try? JSONEncoder().encode(memory), forKey: Self.memoryKey) }
}

private extension FinancialNoticePlanner.Kind {
    static let allValues: [Self] = [.balance, .credits, .characters, .daily, .monthly]
}
