import AppKit
import SwiftUI

/// The popover shown from the menu bar item.
struct MenuBarContentView: View {
    static let width: CGFloat = 360
    /// Keeps countdowns and "Updated … ago" current while the popover is open.
    private static let clockInterval: TimeInterval = 15

    let store: UsageStore

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.clockInterval)) { context in
            VStack(spacing: 0) {
                PopoverHeaderView(
                    isRefreshing: store.isRefreshing,
                    onRefresh: refresh,
                    onOpenSettings: showSettings
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
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch store.content {
        case .loading:
            LoadingStateView()
        case .empty:
            EmptyStateView()
        case .providers(let states):
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
        }
    }

    private func refresh() {
        Task { await store.refresh(trigger: .manual) }
    }

    private func showSettings() {
        // A menu bar app isn't active by default; without this the
        // Settings window would open behind other apps.
        NSApplication.shared.activate()
        openSettings()
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

#Preview("No providers") {
    MenuBarContentView(store: PreviewFixtures.store(codex: .notInstalled, claude: .notInstalled))
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
