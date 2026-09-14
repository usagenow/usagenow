import SwiftUI

/// One provider's section in the popover. Shows only the data the
/// provider actually has; see `ProviderSnapshot.capabilities`.
struct ProviderUsageView: View {
    let state: ProviderState
    let now: Date
    let onRetry: () -> Void

    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderHeaderView(
                provider: state.provider,
                model: snapshot?.recentModel,
                planName: snapshot?.planName,
                note: staleNote
            )
            if state.failure != nil {
                RefreshFailureView(provider: state.provider, isRetrying: state.isRefreshing, onRetry: onRetry)
            }
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var snapshot: ProviderSnapshot? { state.snapshot }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            switch snapshot.status {
            case .available:
                if snapshot.windows.isEmpty {
                    StatusMessage(text: snapshot.quotaUnavailableReason?.message(for: state.provider) ?? String(localized: "Usage limits unavailable"))
                } else {
                    UsageWindowsView(windows: snapshot.windows, now: now)
                }
                ProviderActivityView(activity: snapshot.activity)
                ModelActivityView(models: snapshot.modelActivity)
            case .notAuthenticated:
                StatusMessage(text: String(localized: "Sign in to \(state.provider.displayName) to view usage"))
            case .unavailable:
                StatusMessage(text: String(localized: "Usage limits unavailable"))
            case .notInstalled:
                StatusMessage(text: String(localized: "\(state.provider.displayName) isn’t installed"))
            }
        }
    }

    /// "Updated 18m ago" when the shown data is old.
    private var staleNote: String? {
        guard let snapshot, snapshot.status == .available, snapshot.isStale(at: now) else { return nil }
        return formatter.updatedDescription(snapshot.dataDate, now: now)
    }
}

private struct ProviderHeaderView: View {
    let provider: ProviderID
    let model: String?
    let planName: String?
    let note: String?

    var body: some View {
        HStack(spacing: 8) {
            ProviderLogoTile(provider: provider)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: provider.displayName)
                    .font(.headline)
                if let model {
                    Text(verbatim: ModelNameFormatter.displayName(for: model))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(model)
                }
            }
            Spacer(minLength: 8)
            if let note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let planName {
                Text(verbatim: planName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.badgeFill, in: .capsule)
                    .accessibilityLabel(Text("\(planName) plan"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct StatusMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RefreshFailureView: View {
    let provider: ProviderID
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Couldn’t refresh \(provider.displayName)")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            TextButton(title: "Retry", action: onRetry)
                .disabled(isRetrying)
                .padding(.vertical, -3) // Keep the hover area from growing the row.
                .padding(.trailing, -7) // Align the label, not the highlight, with the content edge.
                .accessibilityLabel(Text("Retry refreshing \(provider.displayName)"))
        }
        .font(.subheadline)
    }
}

/// Local activity. Each value appears only if the provider can observe it;
/// the row disappears when neither is available.
private struct ProviderActivityView: View {
    let activity: LocalActivity

    var body: some View {
        if activity.tokensToday != nil || activity.requestsToday != nil {
            HStack(spacing: 14) {
                if let tokens = activity.tokensToday {
                    MetricLabel(
                        value: UsageFormatter.tokens(tokens),
                        unit: "tokens today",
                        spokenValue: UsageFormatter.count(tokens)
                    )
                }
                if let requests = activity.requestsToday {
                    MetricLabel(
                        value: UsageFormatter.count(requests),
                        unit: requests == 1 ? "request" : "requests"
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }
}

/// Today's activity per model, most active first. Activity only — account
/// limits apply to the account, so no row shows a percentage.
///
/// Hidden when a single model was used: the header already names it and the
/// totals above are its totals.
struct ModelActivityView: View {
    /// Keeps the popover compact; the rest are summarized in one line.
    nonisolated static let maxRows = 3

    let models: [ModelActivity]

    var body: some View {
        if models.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Models today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(models.prefix(Self.maxRows)) { model in
                    row(model)
                }
                if models.count > Self.maxRows {
                    let hidden = models.count - Self.maxRows
                    Text("+\(hidden) more", comment: "Models not listed, e.g. +2 more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 2)
        }
    }

    private func row(_ model: ModelActivity) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: model.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.modelID)
            Spacer(minLength: 8)
            Text(verbatim: UsageFormatter.tokens(model.totalTokens))
                .monospacedDigit()
            Text(verbatim: UsageFormatter.count(model.requests))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.displayName))
        .accessibilityValue(Text(
            "\(UsageFormatter.count(model.totalTokens)) tokens, \(UsageFormatter.count(model.requests)) requests",
            comment: "Model activity, e.g. 72,400,000 tokens, 148 requests"
        ))
    }
}

private struct MetricLabel: View {
    let value: String
    let unit: LocalizedStringKey
    var spokenValue: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(unit))
        .accessibilityValue(spokenValue ?? value)
    }
}
