import SwiftUI

/// One row per quota window the provider reported: label, bar, percentage,
/// and reset time. Renders exactly the windows it's given — never a
/// placeholder for a window that doesn't exist.
struct UsageWindowsView: View {
    let windows: [UsageWindow]
    let now: Date

    @ScaledMetric(relativeTo: .callout) private var labelWidth: CGFloat = 48
    private let columnSpacing: CGFloat = 10
    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(windows) { window in
                row(for: window)
            }
        }
    }

    private func row(for window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: columnSpacing) {
                Text(window.kind.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: labelWidth, alignment: .leading)
                UsageProgressView(usage: window.usage)
                UsagePercentLabel(usage: window.usage)
            }
            if let detail = detailText(for: window) {
                Text(detail)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, labelWidth + columnSpacing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.accessibilityTitle)
        .accessibilityValue(accessibilityValue(for: window))
    }

    /// "Resets in 1h 24m", prefixed with the scope when there is one ("Opus · Resets …").
    private func detailText(for window: UsageWindow) -> String? {
        let reset: String? = window.resetsAt.flatMap { resetsAt in
            if window.usage != nil { return formatter.resetDescription(for: resetsAt, now: now) }
            // Usage unknown because the window reset after the last reading.
            return resetsAt <= now ? formatter.passedResetDescription(for: resetsAt) : nil
        }
        switch (window.scope, reset) {
        case let (scope?, reset?): return "\(scope) · \(reset)"
        case let (scope?, nil): return scope
        case let (nil, reset?): return reset
        case (nil, nil): return nil
        }
    }

    private func accessibilityValue(for window: UsageWindow) -> String {
        guard let usage = window.usage else { return String(localized: "Unavailable") }
        var parts = [String(localized: "\(UsageFormatter.remainingPercent(usage)) left", comment: "Remaining quota, e.g. 58% left")]
        if let level = usage.level.accessibilityDescription { parts.append(level) }
        if let resetsAt = window.resetsAt {
            parts.append(formatter.accessibleResetDescription(for: resetsAt, now: now))
        }
        return parts.joined(separator: ", ")
    }
}

/// "58% left", with a small symbol when little is left.
private struct UsagePercentLabel: View {
    let usage: UsagePercentage?

    @ScaledMetric(relativeTo: .callout) private var minWidth: CGFloat = 72

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let usage {
                if let symbol = usage.level.symbolName {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(usage.level.tint)
                }
                Text(verbatim: UsageFormatter.remainingPercent(usage))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("left", comment: "Follows a remaining percentage, e.g. 58% left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: UsageFormatter.placeholder)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: minWidth, alignment: .trailing)
    }
}
