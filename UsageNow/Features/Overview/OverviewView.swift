import Charts
import SwiftUI

struct OverviewView: View {
    let store: UsageStore
    let accountSets: AccountSets
    @State private var period: OverviewPeriod = .week
    @State private var selectedSource: SourceKey?
    @State private var selectedProvider: ProviderID?

    private var states: [ProviderState] {
        accountSets.displaying(store.states, enabled: store.enabledProviders).filter(\.isVisible)
    }
    private var filteredStates: [ProviderState] { states.filter { selectedProvider == nil || $0.provider == selectedProvider } }

    var body: some View {
        NavigationSplitView {
            List {
                Picker("Providers", selection: $selectedProvider) {
                    Text("Providers").tag(nil as ProviderID?)
                    ForEach(Array(Set(states.map(\.provider))).sorted()) { provider in
                        Text(verbatim: provider.displayName).tag(Optional(provider))
                    }
                }.labelsHidden()
                Button { selectedSource = nil } label: {
                    Label("All accounts", systemImage: "square.grid.2x2")
                        .fontWeight(selectedSource == nil ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .listRowBackground(selectedSource == nil ? Color.accentColor.opacity(0.12) : Color.clear)
                Section("Accounts") {
                    ForEach(filteredStates) { state in
                        Button { selectedSource = state.id } label: {
                            HStack(spacing: 8) {
                                ProviderLogoTile(provider: state.provider)
                                Text(verbatim: state.displayName).lineLimit(2)
                                    .fontWeight(selectedSource == state.id ? .semibold : .regular)
                            }.padding(.vertical, 3)
                        }.buttonStyle(.plain)
                        .listRowBackground(selectedSource == state.id ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Overview").font(.largeTitle.bold())
                            Text("Local activity recorded on this Mac. History may be incomplete.")
                                .foregroundStyle(.secondary)
                        }
                        if states.isEmpty {
                            ContentUnavailableView("No accounts in this set", systemImage: "square.stack.3d.up")
                        }
                        ForEach(filteredStates.filter { selectedSource == nil || $0.id == selectedSource }) { state in
                            if let snapshot = state.snapshot {
                                OverviewAccountCard(state: state, snapshot: snapshot, period: period, now: context.date)
                            }
                        }
                    }.padding(24)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem { AccountSetsPicker(sets: accountSets).frame(maxWidth: 180) }
            ToolbarItem {
                Picker("Period", selection: $period) {
                    ForEach(OverviewPeriod.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 240)
            }
            ToolbarItem {
                Button { Task { await store.refresh(trigger: .manual) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.disabled(store.isRefreshing)
            }
        }
        .onChange(of: states.map(\.id)) {
            if let selectedSource, !states.contains(where: { $0.id == selectedSource }) { self.selectedSource = nil }
            if let selectedProvider, !states.contains(where: { $0.provider == selectedProvider }) { self.selectedProvider = nil }
        }
        .onChange(of: selectedProvider) { selectedSource = nil }
        .frame(minWidth: 740, minHeight: 500)
    }
}

private struct OverviewAccountCard: View {
    let state: ProviderState
    let snapshot: ProviderSnapshot
    let period: OverviewPeriod
    let now: Date
    private var reading: OverviewReading { OverviewReading(snapshot: snapshot, period: period, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProviderLogoTile(provider: snapshot.provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: snapshot.displayName).font(.headline)
                    if let plan = snapshot.planName { Text(verbatim: plan).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if snapshot.isStale(at: now) || state.failure != nil {
                    Label("Stale data", systemImage: "clock").font(.caption).foregroundStyle(.orange)
                }
                Text(ResetTimeFormatter().updatedDescription(snapshot.dataDate, now: now))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if reading.hasActivity {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 26) { activityMetrics }
                    VStack(alignment: .leading, spacing: 12) { activityMetrics }
                }
                if let metric = reading.metric, !reading.days.isEmpty {
                    Chart(reading.days) { day in
                        BarMark(x: .value("Day", day.start, unit: .day), y: .value(metricName(metric), value(day, metric: metric)))
                            .foregroundStyle(Color.accentColor.gradient).cornerRadius(3)
                            .annotation(position: .overlay) { EmptyView() }
                            .accessibilityLabel(Text(day.start.formatted(date: .abbreviated, time: .omitted)))
                            .accessibilityValue(Text(value(day, metric: metric).formatted()))
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .frame(height: 110)
                }
            } else {
                Text("No local activity for this period").foregroundStyle(.secondary)
            }
            if !reading.models.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Models").font(.subheadline.weight(.semibold))
                    ForEach(reading.models.prefix(10)) { model in
                        HStack {
                            Text(verbatim: model.displayName).lineLimit(1)
                            Spacer()
                            Text(verbatim: UsageFormatter.tokens(model.totalTokens)).monospacedDigit()
                            Text("tokens").foregroundStyle(.secondary)
                        }.font(.callout)
                    }
                }
            }
            if let balance = snapshot.balance {
                Divider()
                HStack(alignment: .top, spacing: 24) {
                    if let value = balance.remaining { metric("Balance", UsageFormatter.money(value, currency: balance.currency)) }
                    if let value = balance.spentToday { metric("Reported spend today", UsageFormatter.money(value, currency: balance.currency)) }
                    if let value = balance.spentThisMonth { metric("Reported spend this month", UsageFormatter.money(value, currency: balance.currency)) }
                }
            }
            let windows = snapshot.windows.asOf(now).filter { $0.usage != nil }
            if !windows.isEmpty {
                Divider()
                ForEach(windows) { window in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(window.kind.title)
                            if let scope = window.scope { Text(verbatim: scope).foregroundStyle(.secondary) }
                            Spacer()
                            if let usage = window.usage { Text(verbatim: UsageFormatter.remainingPercent(usage)); Text("left").foregroundStyle(.secondary) }
                        }
                        if let reset = window.resetsAt {
                            Text(ResetTimeFormatter().resetDescription(for: reset, now: now)).foregroundStyle(.secondary).font(.caption)
                        }
                    }.font(.callout)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }

    @ViewBuilder private var activityMetrics: some View {
        if let tokens = reading.tokens { metric("Tokens", UsageFormatter.tokens(tokens)) }
        if let requests = reading.requests { metric("Requests", UsageFormatter.count(requests)) }
        if let credits = reading.credits { metric("Credits", UsageFormatter.credits(credits)) }
        if let cost = reading.estimatedCost {
            metric("API price estimate", (reading.isCostComplete ? "" : "≥ ") + UsageFormatter.money(cost))
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private func metricName(_ metric: ActivityHistory.Metric) -> String {
        switch metric { case .tokens: String(localized: "Tokens"); case .credits: String(localized: "Credits"); case .requests: String(localized: "Requests") }
    }

    private func value(_ day: ActivityHistory.Day, metric: ActivityHistory.Metric) -> Double {
        switch metric { case .tokens: Double(day.tokens); case .credits: NSDecimalNumber(decimal: day.credits ?? 0).doubleValue; case .requests: Double(day.requests) }
    }
}
