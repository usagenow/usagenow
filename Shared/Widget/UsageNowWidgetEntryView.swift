import SwiftUI
import WidgetKit

/// One rendered moment of the widget: the snapshot the app published, or
/// nothing if it hasn't published one yet.
struct UsageNowWidgetEntry: TimelineEntry, Sendable {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct UsageNowWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: UsageNowWidgetEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot?.asOf(entry.date) }

    var body: some View {
        content
            .environment(\.usageAmountStyle, entry.snapshot?.usageAmountStyle ?? .default)
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            switch snapshot.state {
            case .noProvidersEnabled:
                WidgetMessageView(
                    title: "No providers enabled",
                    message: "Open UsageNow to choose providers."
                )
            case .noProvidersDetected:
                WidgetMessageView(
                    title: "No providers detected",
                    message: "Install or use a supported AI coding tool to start tracking usage."
                )
            case .providers(let providers):
                if providers.isEmpty {
                    WidgetMessageView(title: "Selected account unavailable", message: "Edit this widget to choose an enabled provider and account.")
                } else if family == .systemSmall {
                    SmallUsageWidgetView(providers: providers, snapshot: snapshot, now: entry.date)
                } else if family == .systemLarge {
                    LargeUsageWidgetView(snapshot: snapshot, now: entry.date)
                } else {
                    MediumUsageWidgetView(providers: providers, snapshot: snapshot, now: entry.date)
                }
            }
        } else {
            WidgetMessageView(
                title: "Open UsageNow",
                message: "Open UsageNow to load usage data."
            )
        }
    }
}

/// Four detailed rows leave space for two windows and reset times per account.
struct LargeUsageWidgetView: View {
    nonisolated static let maxRows = 4
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let providers = snapshot.providers(fitting: Self.maxRows)
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(updatedAt: staleReadingDate(providers), now: now)
            ForEach(providers) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    WidgetProviderName(provider: provider.provider, name: provider.displayName, updatedAt: provider.updatedAt, now: now)
                    let windows = Array(provider.windows.sortedForDisplay().prefix(2))
                    if windows.isEmpty {
                        WidgetActivityLabel(provider: provider)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if provider.activityText() == nil { WidgetUnavailableLabel() }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(windows) { window in
                                WidgetWindowRow(window: window, now: now)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func staleReadingDate(_ providers: [WidgetProviderSnapshot]) -> Date? {
        let oldest = providers.compactMap(\.updatedAt).min() ?? snapshot.generatedAt
        return now.timeIntervalSince(oldest) > WidgetSnapshot.staleThreshold ? oldest : nil
    }
}

/// A glance: the tightest window of each provider, and the next reset.
struct SmallUsageWidgetView: View {
    let providers: [WidgetProviderSnapshot]
    let snapshot: WidgetSnapshot
    let now: Date

    private let formatter = ResetTimeFormatter()
    @Environment(\.usageAmountStyle) private var style

    /// Two rows leave room for the next reset; three fill the widget.
    nonisolated static let maxRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLayout.contentSpacing) {
            WidgetHeader(updatedAt: staleReadingDate, now: now, compactNote: true)
            if providers.count == 1, let provider = providers.first {
                single(provider)
            } else {
                ForEach(snapshot.providers(fitting: Self.maxRows)) { provider in
                    compact(provider)
                }
                Spacer(minLength: 0)
                if providers.count == 2 {
                    nextReset
                }
            }
        }
    }

    /// One provider gets room for its window name and reset time.
    @ViewBuilder
    private func single(_ provider: WidgetProviderSnapshot) -> some View {
        WidgetProviderName(provider: provider.provider, name: provider.displayName, font: .callout, updatedAt: provider.updatedAt, now: now)
        if let window = provider.mostRelevantWindow ?? provider.windows.sortedForDisplay().first {
            WidgetRemainingLabel(usage: window.usage, font: .title2)
            UsageProgressView(usage: window.usage, height: WidgetLayout.barHeight)
            Text(window.kind.titleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let resetsAt = window.resetsAt {
                WidgetResetLabel(resetsAt: resetsAt, now: now)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            if provider.totals?.isEmpty != false { WidgetUnavailableLabel() }
            activity(provider)
            if let days = provider.recentDays {
                Spacer(minLength: 0)
                WidgetActivityChart(days: days, height: 22)
            }
        }
        Spacer(minLength: 0)
    }

    /// Several providers: one line each.
    @ViewBuilder
    private func compact(_ provider: WidgetProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                WidgetProviderName(provider: provider.provider, name: provider.displayName, font: .caption, updatedAt: provider.updatedAt, now: now)
                Spacer(minLength: 4)
                if provider.mostRelevantWindow != nil {
                    // The bar carries the warning color; keep the name and
                    // its stale-reading marker readable in a small widget.
                    WidgetRemainingLabel(usage: provider.mostRelevantWindow?.usage, font: .caption, showsLevelSymbol: false, compact: true)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            if let window = provider.mostRelevantWindow {
                UsageProgressView(usage: window.usage, height: WidgetLayout.barHeight)
            } else if let days = provider.recentDays {
                WidgetActivityChart(days: days, height: 10)
            } else if provider.totals?.isEmpty == false {
                activity(provider)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                WidgetUnavailableLabel()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: provider.displayName))
        .accessibilityValue(accessibilityValue(for: provider))
    }

    @ViewBuilder
    private var nextReset: some View {
        if let next = snapshot.nextReset(after: now) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next reset")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                WidgetCountdown(resetsAt: next.resetsAt, now: now)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func activity(_ provider: WidgetProviderSnapshot) -> some View {
        WidgetActivityLabel(provider: provider)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var staleReadingDate: Date? {
        let oldest = snapshot.providers(fitting: Self.maxRows).compactMap(\.updatedAt).min() ?? snapshot.generatedAt
        guard now.timeIntervalSince(oldest) > WidgetSnapshot.staleThreshold else { return nil }
        return oldest
    }

    private func accessibilityValue(for provider: WidgetProviderSnapshot) -> String {
        guard let window = provider.mostRelevantWindow, let usage = window.usage else {
            return provider.activityText() ?? String(localized: "Usage limits unavailable")
        }
        var parts = [style.accessibilityDescription(usage)]
        if let resetsAt = window.resetsAt {
            parts.append(formatter.accessibleResetDescription(for: resetsAt, now: now))
        }
        return parts.joined(separator: ", ")
    }
}

/// More detail: each provider's windows side by side, or one row per
/// provider when three or more don't fit as readable columns.
struct MediumUsageWidgetView: View {
    /// Keeps the columns readable; the app shows everything.
    static let maxWindowsPerProvider = 2
    /// Columns stay readable up to this many providers.
    nonisolated static let maxColumns = 2
    nonisolated static let maxRows = 4

    let providers: [WidgetProviderSnapshot]
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLayout.contentSpacing) {
            WidgetHeader(updatedAt: staleReadingDate, now: now)
            if providers.count <= Self.maxColumns {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(providers) { provider in
                        column(provider)
                    }
                }
            } else {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(snapshot.providers(fitting: Self.maxRows)) { provider in
                        WidgetProviderRow(provider: provider, now: now)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func column(_ provider: WidgetProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetProviderName(provider: provider.provider, name: provider.displayName, updatedAt: provider.updatedAt, now: now)
            let windows = Array(provider.windows.sortedForDisplay().prefix(Self.maxWindowsPerProvider))
            if windows.isEmpty {
                if provider.totals?.isEmpty != false { WidgetUnavailableLabel() }
                WidgetActivityLabel(provider: provider)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(windows) { window in
                    WidgetWindowRow(window: window, now: now)
                }
            }
            Spacer(minLength: 0)
            // Two windows fill a column; with fewer there's room for the chart.
            if windows.count < Self.maxWindowsPerProvider, let days = provider.recentDays {
                WidgetActivityChart(days: days)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var staleReadingDate: Date? {
        let oldest = snapshot.providers(fitting: Self.maxRows).compactMap(\.updatedAt).min() ?? snapshot.generatedAt
        guard now.timeIntervalSince(oldest) > WidgetSnapshot.staleThreshold else { return nil }
        return oldest
    }
}
