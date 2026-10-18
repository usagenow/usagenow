import Charts
import SwiftUI

struct QuotaPaceView: View {
    let pace: QuotaPace
    let now: Date

    var body: some View {
        if let estimate = pace.estimate(at: now) {
            DisclosureGroup {
                Chart(pace.points) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Used", point.used.value))
                        .interpolationMethod(.linear)
                        .foregroundStyle(Color.accentColor)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
                .accessibilityLabel(Text("Observed quota usage"))
                Text("Estimate from recent quota readings, not token activity. Your pace can change.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                HStack(spacing: 6) {
                    Text("Quota pace")
                    Text(pace.window.kind.title).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    switch estimate {
                    case .lastsUntilReset:
                        Text("Likely to last until reset").foregroundStyle(.secondary)
                    case .exhaustsBeforeReset(let date):
                        Text("May run out in \(ResetTimeFormatter().countdown(from: now, to: date))")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }
            .help("Estimate from recent quota readings, not token activity. Your pace can change.")
        }
    }
}
