import SwiftUI

/// The same source store backs every icon. The local clock only expires
/// displayed windows; it never polls a provider or reports activity.
struct ProviderMenuBarLabel: View {
    let source: SourceKey
    let store: UsageStore
    let preferences: AppPreferences

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let state = store.states.first(where: { $0.id == source }) {
                ProviderMenuBarReadingLabel(reading: ProviderMenuBarReading(state: state, at: context.date),
                    style: preferences.usageAmountStyle, now: context.date)
            }
        }
    }
}

struct ProviderMenuBarReadingLabel: View {
    let reading: ProviderMenuBarReading
    let style: UsageAmountStyle
    let now: Date

    var body: some View {
        HStack(spacing: 3) {
            ProviderMenuBarIcon(provider: reading.source.provider)
            Text(verbatim: reading.usage.map(style.percent) ?? UsageFormatter.placeholder)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
            if reading.isStale {
                Image(systemName: "clock").font(.system(size: 8))
            }
        }
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: detail))
    }

    private var detail: String {
        var parts = [reading.displayName]
        if let window = reading.window, let usage = window.usage {
            parts.append(window.accessibilityTitle)
            parts.append(style.accessibilityDescription(usage))
            if let reset = window.resetsAt {
                parts.append(ResetTimeFormatter().accessibleResetDescription(for: reset, now: now))
            }
        } else {
            parts.append(String(localized: "Usage limits unavailable"))
        }
        if reading.isStale {
            parts.append(String(localized: "Stale data"))
            if let date = reading.updatedAt { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        }
        return parts.joined(separator: " · ")
    }
}

/// Transparent artwork becomes a monochrome menu bar mark. MiniMax's
/// bundled opaque avatar uses its catalog's neutral symbol here instead
/// of producing a solid template square. Settings keep its full artwork.
struct ProviderMenuBarIcon: View {
    let provider: ProviderID

    var body: some View {
        let definition = ProviderCatalog.definition(for: provider)
        Group {
            if let name = definition.logoAssetName, provider != .minimax {
                Image(name).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: definition.symbolName).resizable().scaledToFit()
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}
