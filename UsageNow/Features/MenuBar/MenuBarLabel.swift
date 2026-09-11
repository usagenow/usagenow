import AppKit
import SwiftUI

/// The item shown in the system menu bar.
struct MenuBarLabel: View {
    private static let hasIconAsset = NSImage(named: "MenuBarIcon") != nil

    let preferences: AppPreferences
    let store: UsageStore

    var body: some View {
        if let usage = preferences.menuBarDisplayMode.usage(in: store.snapshots) {
            HStack(spacing: 4) {
                icon
                // Percent left, matching the popover.
                Text(verbatim: UsageFormatter.remainingPercent(usage))
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
