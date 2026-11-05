import AppKit
import SwiftUI

/// The item shown in the system menu bar.
struct MenuBarLabel: View {
    private static let hasIconAsset = NSImage(named: "MenuBarIcon") != nil

    let preferences: AppPreferences
    let store: UsageStore
    var accountSets: AccountSets? = nil

    var body: some View {
        let choice = accountSets?.menuBarChoice(fallback: preferences.menuBarChoice, states: store.states, enabled: store.enabledProviders) ?? preferences.menuBarChoice
        let snapshots = accountSets?.displaying(store.states, enabled: store.enabledProviders).compactMap(\.snapshot) ?? store.snapshots
        if let usage = choice.mode.usage(in: snapshots, account: choice.account) {
            HStack(spacing: 3) {
                icon
                // Left or used, matching the popover. Set a size rather than
                // taking the default: the menu bar's own font is larger than
                // the glyphs around it, so an unsized number sticks out.
                Text(verbatim: preferences.usageAmountStyle.percent(usage))
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
