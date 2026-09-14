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
    func update(states: [ProviderState], enabledProviders: Set<ProviderID>) {
        guard let store else { return }
        let snapshot = Self.makeSnapshot(states: states, enabledProviders: enabledProviders, generatedAt: now())
        guard snapshot.state != lastWritten?.state else { return }

        do {
            try store.write(snapshot)
            lastWritten = snapshot
            reloadTimelines()
        } catch {
            Log.app.debug("Couldn’t write the widget snapshot")
        }
    }

    static func makeSnapshot(states: [ProviderState], enabledProviders: Set<ProviderID>, generatedAt: Date) -> WidgetSnapshot {
        guard !enabledProviders.isEmpty else {
            return WidgetSnapshot(generatedAt: generatedAt, state: .noProvidersEnabled)
        }
        let providers = states
            .filter { enabledProviders.contains($0.provider) }
            .compactMap(makeProviderSnapshot)
        return WidgetSnapshot(
            generatedAt: generatedAt,
            state: providers.isEmpty ? .noProvidersDetected : .providers(providers)
        )
    }

    /// Copies only display values. Providers that aren't installed, or that
    /// never loaded, are left out entirely.
    private static func makeProviderSnapshot(_ state: ProviderState) -> WidgetProviderSnapshot? {
        guard let snapshot = state.snapshot, snapshot.status != .notInstalled else { return nil }
        return WidgetProviderSnapshot(
            provider: snapshot.provider,
            planName: snapshot.planName,
            modelName: snapshot.recentModel,
            // A window known only to have reset has nothing to show at a glance.
            windows: snapshot.windows.filter { $0.usage != nil || ($0.resetsAt ?? .distantFuture) > snapshot.updatedAt },
            tokensToday: snapshot.activity.tokensToday,
            requestsToday: snapshot.activity.requestsToday,
            quotaUnavailableReason: snapshot.windows.isEmpty ? snapshot.quotaUnavailableReason : nil
        )
    }
}
