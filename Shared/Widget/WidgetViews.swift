import SwiftUI

/// Shared pieces of the desktop widget. The widget renders a snapshot the
/// main app produced and nothing else — no providers, files, credentials,
/// or network access live on this side.
enum WidgetLayout {
    static let contentSpacing: CGFloat = 8
    static let barHeight: CGFloat = 4
}

/// Small brand line: the symbol plus the name, quieter than the data.
struct WidgetHeader: View {
    var note: String?

    var body: some View {
        HStack(spacing: 5) {
            UsageNowSymbolShape()
                .fill(.secondary)
                .aspectRatio(UsageNowSymbolShape.aspectRatio, contentMode: .fit)
                .frame(height: 10)
            Text(verbatim: AppInfo.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "58% left", with a warning glyph when little is left.
struct WidgetRemainingLabel: View {
    let usage: UsagePercentage?
    var font: Font = .callout

    var body: some View {
        HStack(spacing: 3) {
            if let usage, usage.level >= .high {
                Image(systemName: usage.level.symbolName ?? "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(usage.level.tint)
                    .accessibilityHidden(true)
            }
            if let usage {
                Text(verbatim: UsageFormatter.remainingPercent(usage))
                    .font(font.weight(.semibold))
                    .monospacedDigit()
                Text("left", comment: "Follows a remaining percentage, e.g. 58% left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: UsageFormatter.placeholder)
                    .font(font.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One quota window: name, bar, remaining, and when it resets.
struct WidgetWindowRow: View {
    let window: UsageWindow
    let now: Date
    var showsResetLine = true

    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: window.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                WidgetRemainingLabel(usage: window.usage, font: .caption)
            }
            UsageProgressView(usage: window.usage, height: WidgetLayout.barHeight)
            if showsResetLine, let resetsAt = window.resetsAt {
                Text(formatter.resetDescription(for: resetsAt, now: now))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.accessibilityTitle)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let usage = window.usage else { return String(localized: "Unavailable") }
        var parts = [String(localized: "\(UsageFormatter.remainingPercent(usage)) left", comment: "Remaining quota, e.g. 58% left")]
        if let resetsAt = window.resetsAt {
            parts.append(formatter.accessibleResetDescription(for: resetsAt, now: now))
        }
        return parts.joined(separator: ", ")
    }
}

/// Provider name with its logo, sized for a widget.
struct WidgetProviderName: View {
    let provider: ProviderID
    var font: Font = .subheadline

    var body: some View {
        HStack(spacing: 5) {
            ProviderLogo(provider: provider)
                .frame(width: 12, height: 12)
            Text(verbatim: provider.displayName)
                .font(font.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown when quota is missing — short, with troubleshooting left to the app.
struct WidgetUnavailableLabel: View {
    var body: some View {
        Text("Usage limits unavailable")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
    }
}

/// Empty states. They never show numbers, only what to do next.
struct WidgetMessageView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader()
            Spacer(minLength: 0)
            Text(title)
                .font(.callout.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
