import AppKit
import SwiftUI

/// The same source store backs every icon. The local clock only expires
/// displayed windows; it never polls a provider or reports activity.
struct ProviderMenuBarLabel: View {
    let source: SourceKey
    let store: UsageStore
    let preferences: AppPreferences
    let clock: MenuBarClock

    var body: some View {
        if let state = store.states.first(where: { $0.id == source }) {
            ProviderMenuBarReadingLabel(reading: ProviderMenuBarReading(state: state, at: clock.now),
                style: preferences.usageAmountStyle, now: clock.now)
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

/// MenuBarExtra extracts an NSImage from its label and can ignore SwiftUI
/// frame/resizable modifiers. Resize the actual image, not the surrounding view.
struct ProviderMenuBarIcon: View {
    let provider: ProviderID

    var body: some View {
        Image(nsImage: ProviderMenuBarArtwork.image(for: provider))
            .renderingMode(.template)
            .accessibilityHidden(true)
    }
}

@MainActor
enum ProviderMenuBarArtwork {
    static let size = NSSize(width: 15, height: 15)
    private static var images: [ProviderID: NSImage] = [:]

    static func image(for provider: ProviderID) -> NSImage {
        if let image = images[provider] { return image }
        let definition = ProviderCatalog.definition(for: provider)
        let source: NSImage?
        if provider == .antigravity {
            // The older color PNG has an opaque white background. Use the
            // official transparent single-color mark for this template image.
            source = NSImage(named: "AntigravityMenuBarIcon")
        } else if let name = definition.logoAssetName, provider != .minimax {
            source = NSImage(named: name)
        } else {
            source = NSImage(systemSymbolName: definition.symbolName, accessibilityDescription: nil)
        }
        let original = source ?? NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: nil)!
        let originalSize = original.size
        let scale = min(size.width / max(1, originalSize.width), size.height / max(1, originalSize.height))
        let drawingSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let image = NSImage(size: size, flipped: false) { bounds in
            let rect = NSRect(x: bounds.midX - drawingSize.width / 2, y: bounds.midY - drawingSize.height / 2,
                width: drawingSize.width, height: drawingSize.height)
            original.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        images[provider] = image
        return image
    }
}
