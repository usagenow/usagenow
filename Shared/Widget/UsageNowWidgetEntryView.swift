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

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch snapshot.state {
            case .noProvidersEnabled:
                WidgetMessageView(
                    title: "No providers enabled",
                    message: "Open UsageNow to choose providers."
                )
            case .noProvidersDetected:
                WidgetMessageView(
                    title: "No providers detected",
                    message: "Install or use Codex or Claude Code to start tracking usage."
                )
            case .providers(let providers):
                if family == .systemSmall {
                    SmallUsageWidgetView(providers: providers, snapshot: snapshot, now: entry.date)
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

/// A glance: the tightest window of each provider, and the next reset.
struct SmallUsageWidgetView: View {
    let providers: [WidgetProviderSnapshot]
    let snapshot: WidgetSnapshot
    let now: Date

    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLayout.contentSpacing) {
            WidgetHeader(note: staleNote)
            if providers.count == 1, let provider = providers.first {
                single(provider)
            } else {
                ForEach(providers) { provider in
                    compact(provider)
                }
                Spacer(minLength: 0)
                nextReset
            }
        }
    }

    /// One provider gets room for its window name and reset time.
    @ViewBuilder
    private func single(_ provider: WidgetProviderSnapshot) -> some View {
        WidgetProviderName(provider: provider.provider, font: .callout)
        if let window = provider.mostRelevantWindow {
            WidgetRemainingLabel(usage: window.usage, font: .title2)
            UsageProgressView(usage: window.usage, height: WidgetLayout.barHeight)
            Text(verbatim: window.kind.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let resetsAt = window.resetsAt {
                Text(formatter.resetDescription(for: resetsAt, now: now))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            WidgetUnavailableLabel()
            activity(provider)
        }
        Spacer(minLength: 0)
    }

    /// Two providers: one line each.
    @ViewBuilder
    private func compact(_ provider: WidgetProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                WidgetProviderName(provider: provider.provider, font: .caption)
                Spacer(minLength: 4)
                if provider.mostRelevantWindow != nil {
                    WidgetRemainingLabel(usage: provider.mostRelevantWindow?.usage, font: .caption)
                }
            }
            if let window = provider.mostRelevantWindow {
                UsageProgressView(usage: window.usage, height: WidgetLayout.barHeight)
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
                Text(verbatim: formatter.countdown(from: now, to: next.resetsAt))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func activity(_ provider: WidgetProviderSnapshot) -> some View {
        if let tokens = provider.tokensToday {
            Text("\(UsageFormatter.tokens(tokens)) tokens today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var staleNote: String? {
        guard snapshot.isStale(at: now) else { return nil }
        return formatter.updatedDescription(snapshot.generatedAt, now: now)
    }

    private func accessibilityValue(for provider: WidgetProviderSnapshot) -> String {
        guard let window = provider.mostRelevantWindow, let usage = window.usage else {
            return String(localized: "Usage limits unavailable")
        }
        var parts = [String(localized: "\(UsageFormatter.remainingPercent(usage)) left", comment: "Remaining quota, e.g. 58% left")]
        if let resetsAt = window.resetsAt {
            parts.append(formatter.accessibleResetDescription(for: resetsAt, now: now))
        }
        return parts.joined(separator: ", ")
    }
}

/// More detail: each provider's windows side by side.
struct MediumUsageWidgetView: View {
    /// Keeps the columns readable; the app shows everything.
    static let maxWindowsPerProvider = 2

    let providers: [WidgetProviderSnapshot]
    let snapshot: WidgetSnapshot
    let now: Date

    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLayout.contentSpacing) {
            WidgetHeader(note: staleNote)
            HStack(alignment: .top, spacing: 16) {
                ForEach(providers) { provider in
                    column(provider)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func column(_ provider: WidgetProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetProviderName(provider: provider.provider)
            let windows = Array(provider.windows.sortedForDisplay().prefix(Self.maxWindowsPerProvider))
            if windows.isEmpty {
                WidgetUnavailableLabel()
                if let tokens = provider.tokensToday {
                    Text("\(UsageFormatter.tokens(tokens)) tokens today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(windows) { window in
                    WidgetWindowRow(window: window, now: now)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var staleNote: String? {
        guard snapshot.isStale(at: now) else { return nil }
        return formatter.updatedDescription(snapshot.generatedAt, now: now)
    }
}
