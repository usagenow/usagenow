import Charts
import SwiftUI

/// The last 30 days of local activity: a bar per day, and the period's totals
/// beneath. Hovering a bar puts that day's numbers in place of the totals.
///
/// Hidden when nothing was recorded in the period, so a provider that was
/// just installed doesn't show an empty chart.
struct ActivityHistoryView: View {
    let history: ActivityHistory
    var calendar: Calendar = .autoupdatingCurrent

    @State private var hoveredDay: Date?

    var body: some View {
        if history.hasActivity {
            VStack(alignment: .leading, spacing: 4) {
                chart
                caption
            }
            .padding(.top, 2)
        }
    }

    // MARK: Chart

    private var chart: some View {
        let peak = max(history.days.map(history.value(of:)).max() ?? 0, 1)
        return Chart(history.days) { day in
            let value = history.value(of: day)
            BarMark(
                x: .value("Day", day.start, unit: .day),
                // An empty day keeps a sliver of a bar, so the 30 days read as
                // 30 slots rather than gaps.
                y: .value(metricName, value > 0 ? value : peak * 0.025)
            )
            .foregroundStyle(color(for: day, isEmpty: value == 0))
            .cornerRadius(1.5)
            .accessibilityLabel(Text(day.start.formatted(.dateTime.month(.abbreviated).day())))
            .accessibilityValue(Text(verbatim: dayValues(day).joined(separator: ", ")))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...peak)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let x = location.x - geometry[frame].origin.x
                            hoveredDay = proxy.value(atX: x, as: Date.self).map { calendar.startOfDay(for: $0) }
                        case .ended:
                            hoveredDay = nil
                        }
                    }
            }
        }
        .frame(height: 34)
        .accessibilityLabel(Text("Activity, last 30 days"))
    }

    private func color(for day: ActivityHistory.Day, isEmpty: Bool) -> Color {
        if isEmpty { return Palette.track }
        let isHighlighted = hoveredDay.map { $0 == day.start } ?? calendar.isDateInToday(day.start)
        return Color.accentColor.opacity(isHighlighted ? 1 : 0.55)
    }

    private var metricName: String {
        switch history.metric {
        case .tokens: String(localized: "Tokens")
        case .credits: String(localized: "Credits")
        case .requests: String(localized: "Requests")
        }
    }

    // MARK: Caption

    private var hovered: ActivityHistory.Day? {
        hoveredDay.flatMap { start in history.days.first { $0.start == start } }
    }

    private var caption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let day = hovered {
                Text(verbatim: day.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .foregroundStyle(.secondary)
                Text(verbatim: dayValues(day).joined(separator: " · "))
                    .monospacedDigit()
            } else {
                Text("Last 30 days")
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: (totalValues + [topModel].compactMap { $0 }).joined(separator: " · "))
                    Text(verbatim: totalValues.joined(separator: " · "))
                }
                .monospacedDigit()
                .help(costHelp)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var totalValues: [String] {
        values(
            tokens: history.tokens,
            requests: history.requests,
            cost: history.estimatedCost,
            isCostComplete: history.isCostComplete,
            credits: history.credits
        )
    }

    private func dayValues(_ day: ActivityHistory.Day) -> [String] {
        let values = values(
            tokens: day.tokens,
            requests: day.requests,
            cost: day.estimatedCost,
            isCostComplete: day.isCostComplete,
            credits: day.credits
        )
        return values.isEmpty ? [String(localized: "No activity")] : values
    }

    /// The numbers worth showing for this metric, most telling first: cost
    /// where tokens can be priced, the tool's own meter otherwise.
    private func values(tokens: Int64, requests: Int64, cost: Decimal?, isCostComplete: Bool, credits: Decimal?) -> [String] {
        var values: [String] = []
        switch history.metric {
        case .tokens:
            if let cost {
                // A trailing "+" marks an estimate that leaves some models out.
                values.append("≈ " + UsageFormatter.money(cost) + (isCostComplete ? "" : "+"))
            }
            if tokens > 0 {
                values.append(String(localized: "\(UsageFormatter.tokens(tokens)) tokens", comment: "e.g. 2.18B tokens"))
            }
        case .credits:
            if let credits, credits > 0 {
                values.append(String(localized: "\(UsageFormatter.credits(credits)) credits", comment: "e.g. 12.5 credits"))
            }
            if requests > 0 {
                values.append(requestsText(requests))
            }
        case .requests:
            if requests > 0 {
                values.append(requestsText(requests))
            }
        }
        return values
    }

    /// "1,204 requests": the grouped number, then the word in the form
    /// that number takes.
    private func requestsText(_ requests: Int64) -> String {
        UsageFormatter.count(requests) + " " + UsageFormatter.requestsUnit(requests)
    }

    private var topModel: String? {
        history.topModel.map { ModelNameFormatter.shortName(for: $0) }
    }

    private var costHelp: Text {
        guard history.estimatedCost != nil else { return Text(verbatim: "") }
        return history.isCostComplete
            ? Text("What these tokens would cost at published API prices. Your subscription doesn't charge per token.")
            : Text("What these tokens would cost at published API prices, for the models UsageNow has a price for. Your subscription doesn't charge per token.")
    }
}

extension EnvironmentValues {
    /// Whether the popover shows the 30-day chart. Set from Settings.
    @Entry var showsActivityHistory = true
}

#if DEBUG
#Preview("Tokens") {
    ActivityHistoryView(history: PreviewFixtures.history(.tokens))
        .padding()
        .frame(width: 360)
}

#Preview("Credits") {
    ActivityHistoryView(history: PreviewFixtures.history(.credits))
        .padding()
        .frame(width: 360)
}
#endif
