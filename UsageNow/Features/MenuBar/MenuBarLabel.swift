import AppKit
import SwiftUI

/// The item shown in the system menu bar.
struct MenuBarLabel: View {
    private static let hasIconAsset = NSImage(named: "MenuBarIcon") != nil

    let preferences: AppPreferences
    let store: UsageStore

    var body: some View {
        if let usage = preferences.menuBarDisplayMode.usage(in: store.snapshots) {
            HStack(spacing: 3) {
                icon
                // Percent left, matching the popover. Set a size rather than
                // taking the default: the menu bar's own font is larger than
                // the glyphs around it, so an unsized number sticks out.
                Text(verbatim: UsageFormatter.remainingPercent(usage))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
            }
        } else {
            icon
        }
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            if Self.hasIconAsset {
                Image("MenuBarIcon")
                    .renderingMode(.template)
            } else {
                Image(systemName: "chart.bar.fill")
            }
        }
        .accessibilityLabel(Text(verbatim: AppInfo.name))
    }
}
