import Foundation
import Observation

/// Central usage state: loads provider snapshots, refreshes them
/// concurrently, and exposes normalized results to the UI.
@Observable
@MainActor
final class UsageStore {
    enum Content: Equatable {
        case loading
        case empty
        case providers([ProviderState])
    }

    /// One entry per known provider, in display order.
    private(set) var states: [ProviderState]
    private(set) var isRefreshing = false
    private(set) var hasCompletedInitialLoad: Bool
    /// When the last refresh attempt finished.
    private(set) var lastRefreshAt: Date?

    @ObservationIgnored private let providers: [any UsageProvider]
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var inFlightRefresh: Task<Void, Never>?

    /// - Parameters:
    ///   - states: Seed state, for previews and tests.
    init(
        providers: [any UsageProvider],
        states: [ProviderState] = [],
        hasCompletedInitialLoad: Bool = false,
        lastRefreshAt: Date? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.providers = providers
        self.now = now
        self.hasCompletedInitialLoad = hasCompletedInitialLoad
        self.lastRefreshAt = lastRefreshAt

        let seeded = Dictionary(states.map { ($0.provider, $0) }, uniquingKeysWith: { _, last in last })
        let ids = Set(providers.map(\.id)).union(seeded.keys).sorted()
        self.states = ids.map { seeded[$0] ?? ProviderState(provider: $0) }
    }

    var content: Content {
        let visible = states.filter(\.isVisible)
        if !visible.isEmpty { return .providers(visible) }
        return hasCompletedInitialLoad ? .empty : .loading
    }

    /// Latest snapshots of all providers, including not-installed ones.
    var snapshots: [ProviderSnapshot] {
        states.compactMap(\.snapshot)
    }

    var hasFailures: Bool {
        states.contains { $0.isVisible && $0.failure != nil }
    }

    /// Refreshes all providers, or only `ids`. Calls made while a refresh is
    /// in flight wait for it instead of starting another.
    func refresh(only ids: Set<ProviderID>? = nil, trigger: RefreshTrigger = .automatic) async {
        if let inFlightRefresh {
            await inFlightRefresh.value
            return
        }
        let targets = providers.filter { ids?.contains($0.id) ?? true }
        let task = Task { await performRefresh(of: targets, trigger: trigger) }
        inFlightRefresh = task
        await task.value
        inFlightRefresh = nil
    }

    /// Refreshes unless the last refresh finished less than `maxAge` ago.
    func refreshIfNeeded(maxAge: TimeInterval) async {
        if let lastRefreshAt, now().timeIntervalSince(lastRefreshAt) < maxAge { return }
        await refresh()
    }

    private func performRefresh(of targets: [any UsageProvider], trigger: RefreshTrigger) async {
        isRefreshing = true
        for provider in targets {
            update(provider.id) { $0.isRefreshing = true }
        }

        await withTaskGroup(of: (ProviderID, Result<ProviderSnapshot, any Error>).self) { group in
            for provider in targets {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.fetchSnapshot(trigger: trigger)))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            // Apply each result as it arrives so a slow provider doesn't hold back the others.
            for await (id, result) in group {
                apply(result, to: id)
            }
        }

        isRefreshing = false
        hasCompletedInitialLoad = true
        lastRefreshAt = now()
    }

    private func apply(_ result: Result<ProviderSnapshot, any Error>, to id: ProviderID) {
        let date = now()
        update(id) { state in
            state.isRefreshing = false
            switch result {
            case .success(let snapshot):
                state.snapshot = snapshot
                state.failure = nil
            case .failure(let error) where error is CancellationError:
                break
            case .failure(let error):
                Log.provider.error("Refresh failed for \(id.rawValue, privacy: .public): \(error.localizedDescription)")
                state.failure = RefreshFailure(message: error.localizedDescription, date: date)
            }
        }
    }

    private func update(_ id: ProviderID, _ body: (inout ProviderState) -> Void) {
        guard let index = states.firstIndex(where: { $0.provider == id }) else { return }
        body(&states[index])
    }
}
