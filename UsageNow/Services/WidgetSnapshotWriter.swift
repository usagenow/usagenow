import Foundation
import WidgetKit

/// Publishes the widget's view of the world.
///
/// This is the only path from provider data to the widget: the widget
/// never runs providers, reads `~/.codex` or `~/.claude`, touches the
/// keychain, or calls any endpoint. Everything it shows passes through
/// here, where disabled and not-installed providers are dropped and each
/// field is copied explicitly — no provider internals are serialized.
@MainActor
final class WidgetSnapshotWriter {
    private let store: WidgetSnapshotStore?
    private let reloadTimelines: @Sendable () -> Void
    private let now: () -> Date
    private var lastWritten: WidgetSnapshot?

    init(
        store: WidgetSnapshotStore? = WidgetSnapshotStore.shared(),
        reloadTimelines: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        now: @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.reloadTimelines = reloadTimelines
        self.now = now
    }

    /// Writes the snapshot, and reloads widget timelines only when what the
    /// widget would show actually changed.
    func update(states: [ProviderState], enabledProviders: Set<ProviderID>, style: UsageAmountStyle = .default, includesRecentDays: Bool = true) {
        guard let store else { return }
        var snapshot = Self.makeSnapshot(states: states, enabledProviders: enabledProviders, generatedAt: now(), includesRecentDays: includesRecentDays)
        snapshot.usageAmountStyle = style
        guard snapshot.state != lastWritten?.state || snapshot.usageAmountStyle != lastWritten?.usageAmountStyle else { return }

        do {
            try store.write(snapshot)
            lastWritten = snapshot
            reloadTimelines()
        } catch {
            Log.app.debug("Couldn’t write the widget snapshot")
        }
    }

    /// - Parameter includesRecentDays: Follows **Show the last 30 days**, so
    ///   turning the charts off in the app turns them off on the desktop too.
    static func makeSnapshot(
        states: [ProviderState],
        enabledProviders: Set<ProviderID>,
        generatedAt: Date,
        includesRecentDays: Bool = true
    ) -> WidgetSnapshot {
        guard !enabledProviders.isEmpty else {
            return WidgetSnapshot(generatedAt: generatedAt, state: .noProvidersEnabled)
        }
        let providers = states
            .filter { enabledProviders.contains($0.provider) }
            .compactMap { makeProviderSnapshot($0, includesRecentDays: includesRecentDays) }
        return WidgetSnapshot(
            generatedAt: generatedAt,
            state: providers.isEmpty ? .noProvidersDetected : .providers(providers)
        )
    }

    /// Copies only display values. Providers that aren't installed, or that
    /// never loaded, are left out entirely.
    private static func makeProviderSnapshot(_ state: ProviderState, includesRecentDays: Bool) -> WidgetProviderSnapshot? {
        guard let snapshot = state.snapshot, snapshot.status != .notInstalled else { return nil }
        return WidgetProviderSnapshot(
            provider: snapshot.provider,
            planName: snapshot.planName,
            modelName: snapshot.recentModel,
            // A window known only to have reset has nothing to show at a glance.
            windows: snapshot.windows.filter { $0.usage != nil || ($0.resetsAt ?? .distantFuture) > snapshot.updatedAt },
            tokensToday: snapshot.activity.tokensToday,
            requestsToday: snapshot.activity.requestsToday,
            creditsToday: snapshot.activity.creditsToday,
            quotaUnavailableReason: snapshot.windows.isEmpty ? snapshot.quotaUnavailableReason : nil,
            recentDays: includesRecentDays ? snapshot.activity.history.flatMap(recentDays) : nil
        )
    }

    /// The last two weeks as shares of the busiest day, rounded so a small
    /// change in today's total doesn't reload the widget. Amounts stay in
    /// the app.
    static func recentDays(_ history: ActivityHistory) -> [Double]? {
        guard history.hasActivity else { return nil }
        let values = history.days.suffix(WidgetProviderSnapshot.recentDayCount).map { history.value(of: $0) }
        guard let peak = values.max(), peak > 0 else { return nil }
        return values.map { ($0 / peak * 100).rounded() / 100 }
    }
}
