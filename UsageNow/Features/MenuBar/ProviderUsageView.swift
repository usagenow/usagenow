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
                if let balance = snapshot.balance {
                    AccountBalanceView(balance: balance)
                }
                if !snapshot.windows.isEmpty {
                    UsageWindowsView(windows: snapshot.windows, now: now)
                }
                // Also under windows that are only known to have reset, so the fix stays visible.
                // A balance is the reading for API accounts, so its absence of windows isn't news.
                if (snapshot.windows.isEmpty && snapshot.balance == nil) || snapshot.quotaUnavailableReason != nil {
                    StatusMessage(text: snapshot.quotaUnavailableReason?.message(for: state.provider) ?? String(localized: "Usage limits unavailable"))
                }
                ProviderActivityView(activity: snapshot.activity)
                ModelActivityView(models: snapshot.modelActivity)
            case .notAuthenticated where ProviderCatalog.definition(for: state.provider).apiKey != nil:
                StatusMessage(text: String(localized: "\(state.provider.displayName) didn’t accept the API key. Check it in Settings › Providers."))
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
        if activity.tokensToday != nil || activity.requestsToday != nil || activity.creditsToday != nil {
            HStack(spacing: 14) {
                if let tokens = activity.tokensToday {
                    MetricLabel(
                        value: UsageFormatter.tokens(tokens),
                        unit: "tokens today",
                        spokenValue: UsageFormatter.count(tokens)
                    )
                }
                if let credits = activity.creditsToday {
                    MetricLabel(
                        value: UsageFormatter.credits(credits),
                        unit: activity.isCreditsComplete ? "credits today" : "credits today, partial"
                    )
                }
                if let requests = activity.requestsToday {
                    MetricLabel(
                        value: UsageFormatter.count(requests),
                        unit: requests == 1 ? "request" : "requests"
                    )
                }
                if let cost = activity.estimatedCostToday {
                    // "≈" and "at API prices" together say this is what the
                    // tokens would have cost, not what anyone was charged.
                    MetricLabel(
                        value: "≈ " + UsageFormatter.money(cost),
                        unit: activity.isCostComplete ? "at API prices" : "at API prices, partial",
                        spokenValue: String(localized: "about \(UsageFormatter.money(cost))")
                    )
                    .help(activity.isCostComplete
                          ? Text("What today's tokens would cost at published API prices. Your subscription doesn't charge per token.")
                          : Text("What today's tokens would cost at published API prices, for the models UsageNow has a price for. Your subscription doesn't charge per token."))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }
}

/// Money on an API account, as its provider reports it — never estimated.
private struct AccountBalanceView: View {
    let balance: AccountBalance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                if let remaining = balance.remaining {
                    MetricLabel(value: UsageFormatter.money(remaining, currency: balance.currency), unit: "left")
                }
                if let today = balance.spentToday {
                    MetricLabel(value: UsageFormatter.money(today, currency: balance.currency), unit: "spent today")
                }
                if let month = balance.spentThisMonth {
                    MetricLabel(value: UsageFormatter.money(month, currency: balance.currency), unit: "this month")
                }
                Spacer(minLength: 0)
            }
            if !balance.canMakeRequests {
                Label("The balance can’t pay for more requests.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 2)
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
            Text(verbatim: model.isRequestCountKnown ? UsageFormatter.count(model.requests) : "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.displayName))
        .accessibilityValue(model.isRequestCountKnown
            ? Text(
                "\(UsageFormatter.count(model.totalTokens)) tokens, \(UsageFormatter.count(model.requests)) requests",
                comment: "Model activity, e.g. 72,400,000 tokens, 148 requests"
            )
            : Text("\(UsageFormatter.count(model.totalTokens)) tokens", comment: "Model activity without a request count"))
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
