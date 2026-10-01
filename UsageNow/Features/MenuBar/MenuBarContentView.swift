import AppKit
import SwiftUI

/// The popover shown from the menu bar item.
struct MenuBarContentView: View {
    static let width: CGFloat = 360
    /// Keeps countdowns and "Updated … ago" current while the popover is open.
    private static let clockInterval: TimeInterval = 15

    let store: UsageStore
    var navigation = SettingsNavigation()
    /// Opens Settings where the environment's action can't: outside a
    /// SwiftUI scene, in the panel the global shortcut shows.
    var openSettingsOverride: (@MainActor () -> Void)?

    /// The providers' natural height, measured outside the scroll view so
    /// the popover can match it exactly while it fits on screen.
    @State private var providersHeight: CGFloat?

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.clockInterval)) { context in
            VStack(spacing: 0) {
                PopoverHeaderView(
                    isRefreshing: store.isRefreshing,
                    onRefresh: refresh,
                    onOpenSettings: { showSettings(.general) }
                )
                Divider()
                content(now: context.date)
                Divider()
                PopoverFooterView(
                    lastRefreshAt: store.lastRefreshAt,
                    hasFailures: store.hasFailures,
                    now: context.date
                )
            }
        }
        .frame(width: Self.width)
        .background(Palette.popoverBackdrop)
    }

    /// The most the provider list may take before it scrolls: the screen's
    /// usable height, less the header, footer, and a margin below. With many
    /// providers and their charts, the popover would otherwise run off a
    /// small screen.
    private var maxProvidersHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(240, screen - 120)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch store.content {
        case .loading:
            LoadingStateView()
        case .empty:
            EmptyStateView()
        case .noProvidersEnabled:
            NoProvidersEnabledView { showSettings(.providers) }
        case .providers(let states):
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(states) { state in
                        ProviderUsageView(state: state, now: now) {
                            Task { await store.refresh(only: [state.provider], trigger: .manual) }
                        }
                        if state.id != states.last?.id {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { providersHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            // The content's own height, never the window's, decides this, so
            // a resize can't feed back into another one.
            .frame(height: providersHeight.map { min($0, maxProvidersHeight) })
        }
    }

    private func refresh() {
        Task { await store.refresh(trigger: .manual) }
    }

    private func showSettings(_ tab: SettingsTab) {
        navigation.tab = tab
        // A menu bar app isn't active by default; without this the
        // Settings window would open behind other apps.
        NSApplication.shared.activate()
        if let openSettingsOverride { openSettingsOverride() } else { openSettings() }
    }
}

#if DEBUG
#Preview("Normal") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .normal, claude: .normal))
}

#Preview("High usage") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .high, claude: .high))
}

#Preview("Critical usage") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .critical, claude: .high))
}

#Preview("One provider") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .normal, claude: .notInstalled))
}

#Preview("Loading") {
    MenuBarContentView(store: PreviewFixtures.loadingStore())
}

#Preview("Error, stale data") {
    MenuBarContentView(store: PreviewFixtures.errorStore())
}

#Preview("Weekly only") {
    MenuBarContentView(store: PreviewFixtures.weeklyOnlyStore())
}

#Preview("Limits unavailable") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .unavailable, claude: .normal))
}

#Preview("Signed out") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .normal, claude: .notAuthenticated))
}

#Preview("No providers installed") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .notInstalled, claude: .notInstalled))
}

#Preview("No providers enabled") {
    MenuBarContentView(store: PreviewFixtures.noProvidersEnabledStore())
}

#Preview("Dark") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .normal, claude: .normal))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .normal, claude: .normal))
        .preferredColorScheme(.light)
}
#endif
