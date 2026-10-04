import Foundation
import Observation

/// Central usage state: loads provider snapshots, refreshes them
/// concurrently, and exposes normalized results to the UI.
@Observable
@MainActor
final class UsageStore {
    enum Content: Equatable {
        case loading
        /// Providers are enabled, but none is installed on this Mac.
        case empty
        /// Every supported provider is turned off in Settings.
        case noProvidersEnabled
        case providers([ProviderState])
    }

    /// One entry per known provider and added account, in display order.
    private(set) var states: [ProviderState]
    /// Providers the user turned on. Others, and their added accounts, are
    /// never refreshed or shown.
    private(set) var enabledProviders: Set<ProviderID>
    private(set) var isRefreshing = false
    private(set) var hasCompletedInitialLoad: Bool
    /// When the last refresh attempt finished.
    private(set) var lastRefreshAt: Date?

    @ObservationIgnored private var providers: [any UsageProvider]
    @ObservationIgnored private var order: [ProviderID]
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var inFlightRefresh: Task<Void, Never>?

    /// - Parameters:
    ///   - providers: Each provider's own account, followed by any added ones.
    ///   - states: Seed state, for previews and tests.
    init(
        providers: [any UsageProvider],
        enabledProviders: Set<ProviderID> = ProviderCatalog.availableIDs,
        order: [ProviderID] = ProviderCatalog.available.map(\.id),
        states: [ProviderState] = [],
        hasCompletedInitialLoad: Bool = false,
        lastRefreshAt: Date? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.providers = providers
        self.enabledProviders = enabledProviders
        self.order = order
        self.now = now
        self.hasCompletedInitialLoad = hasCompletedInitialLoad
        self.lastRefreshAt = lastRefreshAt
        self.states = []
        self.states = arrangedStates(seeded: states)
    }

    /// Puts providers in the user's order; any not in it follow in catalog
    /// order. A provider's added accounts follow it.
    func setProviderOrder(_ order: [ProviderID]) {
        self.order = order
        let reordered = arrangedStates(seeded: states)
        if reordered != states { states = reordered }
    }

    /// Replaces the added accounts. A new one is read right away; one that
    /// was removed disappears with its reading.
    func setAccounts(_ accountProviders: [any UsageProvider]) async {
        let before = Set(states.map(\.id))
        providers = providers.filter { $0.account == nil } + accountProviders.filter { $0.account != nil }
        let arranged = arrangedStates(seeded: states)
        if arranged != states { states = arranged }
        let added = Set(providers.map(\.sourceKey)).subtracting(before)
        guard !added.isEmpty else { return }
        await refresh(matching: { added.contains($0.sourceKey) }, isParticular: true, trigger: .manual)
    }

    /// A state for every provider and seeded entry, keeping what's known,
    /// with each account's current name.
    private func arrangedStates(seeded: [ProviderState]) -> [ProviderState] {
        let known = Dictionary(seeded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var tags: [SourceKey: AccountTag] = [:]
        var accountOrder: [String] = []
        for provider in providers {
            guard let account = provider.account else { continue }
            tags[provider.sourceKey] = account.tag
            accountOrder.append(account.id)
        }
        // Seeded states without a provider stay (previews and tests), but an
        // account that was removed goes.
        let keys = Set(providers.map(\.sourceKey)).union(known.keys.filter { $0.account == nil || tags[$0] != nil })
        return Self.ordered(keys, by: order, accounts: accountOrder).map { key in
            var state = known[key] ?? ProviderState(provider: key.provider)
            if key.account != nil {
                state.account = tags[key] ?? state.account
                state.snapshot?.account = state.account
            }
            return state
        }
    }

    private static func ordered(_ keys: Set<SourceKey>, by order: [ProviderID], accounts: [String]) -> [SourceKey] {
        func rank(_ key: SourceKey) -> (Int, Int) {
            let provider = order.firstIndex(of: key.provider) ?? (order.count + ProviderID.allCases.firstIndex(of: key.provider)!)
            let account = key.account.map { (accounts.firstIndex(of: $0) ?? accounts.count) + 1 } ?? 0
            return (provider, account)
        }
        return keys.sorted { rank($0) < rank($1) }
    }

    var content: Content {
        if enabledProviders.isEmpty { return .noProvidersEnabled }
        let visible = enabledStates.filter(\.isVisible)
        if !visible.isEmpty { return .providers(visible) }
        return hasCompletedInitialLoad ? .empty : .loading
    }

    /// Latest snapshots of enabled providers, including not-installed ones.
    var snapshots: [ProviderSnapshot] {
        enabledStates.compactMap(\.snapshot)
    }

    var hasFailures: Bool {
        enabledStates.contains { $0.isVisible && $0.failure != nil }
    }

    private var enabledStates: [ProviderState] {
        states.filter { enabledProviders.contains($0.provider) }
    }

    /// Applies a change to the enabled providers: a provider turned off
    /// loses its state immediately, and one turned on is refreshed.
    func setEnabledProviders(_ enabled: Set<ProviderID>) async {
        let newlyEnabled = enabled.subtracting(enabledProviders)
        let disabled = enabledProviders.subtracting(enabled)
        enabledProviders = enabled
        for index in states.indices where disabled.contains(states[index].provider) {
            states[index] = ProviderState(provider: states[index].provider, account: states[index].account)
        }
        guard !newlyEnabled.isEmpty else { return }
        await refresh(only: newlyEnabled)
    }

    /// Refreshes all providers, or only `ids`.
    ///
    /// A routine refresh of everything that arrives while another refresh is
    /// in flight waits for it instead of starting a second one. A request
    /// that asks for something particular — named providers, or a refresh
    /// the person asked for — waits its turn and then runs: the refresh in
    /// flight may have started before the provider was turned on, or before
    /// the key or sign-in it needs was there.
    /// A provider's added accounts are refreshed with it.
    func refresh(only ids: Set<ProviderID>? = nil, trigger: RefreshTrigger = .automatic) async {
        await refresh(
            matching: { provider in ids?.contains(provider.id) ?? true },
            isParticular: ids != nil || trigger != .automatic,
            trigger: trigger
        )
    }

    private func refresh(matching include: (any UsageProvider) -> Bool, isParticular: Bool, trigger: RefreshTrigger) async {
        if let current = inFlightRefresh {
            await current.value
            if !isParticular { return }
            while let next = inFlightRefresh {
                await next.value
            }
        }
        let targets = providers.filter { enabledProviders.contains($0.id) && include($0) }
        guard !targets.isEmpty else {
            hasCompletedInitialLoad = true
            lastRefreshAt = now()
            return
        }
        // The task clears itself, so whoever waited on it finds the way
        // clear as soon as it resumes.
        let task = Task {
            await performRefresh(of: targets, trigger: trigger)
            inFlightRefresh = nil
        }
        inFlightRefresh = task
        await task.value
    }

    /// Refreshes unless the last refresh finished less than `maxAge` ago.
    func refreshIfNeeded(maxAge: TimeInterval) async {
        if let lastRefreshAt, now().timeIntervalSince(lastRefreshAt) < maxAge { return }
        await refresh()
    }

    private func performRefresh(of targets: [any UsageProvider], trigger: RefreshTrigger) async {
        isRefreshing = true
        for provider in targets {
            update(provider.sourceKey) { $0.isRefreshing = true }
        }

        await withTaskGroup(of: (SourceKey, Result<ProviderSnapshot, any Error>).self) { group in
            for provider in targets {
                group.addTask {
                    do {
                        return (provider.sourceKey, .success(try await provider.fetchSnapshot(trigger: trigger)))
                    } catch {
                        return (provider.sourceKey, .failure(error))
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

    private func apply(_ result: Result<ProviderSnapshot, any Error>, to id: SourceKey) {
        let date = now()
        update(id) { state in
            state.isRefreshing = false
            switch result {
            case .success(var snapshot):
                snapshot.account = state.account
                state.snapshot = snapshot
                state.failure = nil
            case .failure(let error) where error is CancellationError:
                break
            case .failure(let error):
                Log.provider.error("Refresh failed for \(id.provider.rawValue, privacy: .public): \(error.localizedDescription)")
                state.failure = RefreshFailure(message: error.localizedDescription, date: date)
            }
        }
    }

    private func update(_ id: SourceKey, _ body: (inout ProviderState) -> Void) {
        guard let index = states.firstIndex(where: { $0.id == id }) else { return }
        body(&states[index])
    }
}
