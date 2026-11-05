import SwiftUI

/// Rows inside Notifications; the master notification consent and quiet-hours
/// controls are shared with quota alerts, while amounts belong to each account.
struct FinancialSettingsView: View {
    @Bindable var preferences: AppPreferences
    let states: [ProviderState]

    var body: some View {
        Section("Balance and budgets") {
            Text("Alerts only. Budgets do not block spending. Reported spend uses the provider’s time zone; API price estimates are excluded.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(states.filter { ProviderCatalog.definition(for: $0.provider).apiKey != nil }) { state in
                DisclosureGroup {
                    if let snapshot = state.snapshot, snapshot.status == .available,
                       snapshot.balance != nil || !snapshot.totals.isEmpty {
                        controls(state: state, snapshot: snapshot)
                    } else {
                        Text("Read fresh account data to configure financial alerts.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !preferences.financialPolicy.rule(for: state.id).isEmpty {
                            Button("Remove", role: .destructive) { preferences.financialPolicy.rules.removeValue(forKey: state.id.description) }
                        }
                    }
                } label: { Text(verbatim: state.displayName) }
            }
        }
    }

    @ViewBuilder private func controls(state: ProviderState, snapshot: ProviderSnapshot) -> some View {
        if let balance = snapshot.balance {
            Text(verbatim: balance.currency).font(.caption).foregroundStyle(.secondary)
            if balance.remaining != nil { amount("Low balance", path: \.balanceBelow, source: state.id, currency: balance.currency, initial: 5) }
            if balance.spendingTimeZoneID != nil {
                if balance.spentToday != nil { amount("Daily budget", path: \.dailyBudget, source: state.id, currency: balance.currency, initial: 10) }
                if balance.spentThisMonth != nil { amount("Monthly budget", path: \.monthlyBudget, source: state.id, currency: balance.currency, initial: 50) }
                Text("Budget alerts at 80% and 100% of reported spend.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let rule = preferences.financialPolicy.rule(for: state.id)
            if let currency = rule.currency, currency != balance.currency {
                Text("The account currency changed. Configure monetary alerts again.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        if snapshot.totals.contains(where: { $0.kind == .creditsRemaining }) {
            amount("Low credits", path: \.creditsBelow, source: state.id, initial: 100)
        }
        if snapshot.totals.contains(where: { $0.kind == .charactersRemaining }) {
            amount("Low characters", path: \.charactersBelow, source: state.id, initial: 10000)
        }
    }

    private func amount(_ title: LocalizedStringKey, path: WritableKeyPath<FinancialPolicy.Rule, Decimal?>,
                        source: SourceKey, currency: String? = nil, initial: Decimal) -> some View {
        let rule = preferences.financialPolicy.rule(for: source)
        return HStack {
            Toggle(title, isOn: Binding(get: { rule[keyPath: path] != nil }, set: { enabled in
                set(enabled ? initial : nil, path: path, source: source, currency: currency)
            }))
            if let value = rule[keyPath: path] {
                TextField("Amount", value: Binding(get: { value }, set: {
                    set($0.isNaN ? nil : max(0, $0), path: path, source: source, currency: currency)
                }), format: .number)
                .frame(width: 95).multilineTextAlignment(.trailing)
                .accessibilityLabel(Text(title))
            }
        }
    }

    private func set(_ value: Decimal?, path: WritableKeyPath<FinancialPolicy.Rule, Decimal?>, source: SourceKey, currency: String?) {
        var policy = preferences.financialPolicy
        var rule = policy.rule(for: source)
        if let currency, rule.currency != currency {
            rule.balanceBelow = nil; rule.dailyBudget = nil; rule.monthlyBudget = nil
            rule.currency = currency
        }
        rule[keyPath: path] = value
        if rule.isEmpty { policy.rules.removeValue(forKey: source.description) }
        else { policy.rules[source.description] = rule }
        preferences.financialPolicy = policy
    }
}
