import AppKit
import Foundation
import Network
import Observation

/// Per-account, bounded polling. Comparisons use safe numeric content only;
/// no process inspection, credential reads or session scans are performed here.
struct AdaptiveRefreshPolicy {
    struct Conditions: Equatable, Sendable {
        var online = true
        var screenLocked = false
        var lowPower = false
    }

    struct Record {
        var attemptedAt: Date
        var content: Content?
        var unchanged = 0
        var failures = 0
    }

    struct Content: Equatable {
        var status: ProviderStatus
        var windows: [UsageWindow]
        var tokens: Int64?
        var requests: Int64?
        var credits: Decimal?
        var balance: AccountBalance?
        var totals: [UsageTotal]
        init(_ snapshot: ProviderSnapshot) {
            status = snapshot.status
            windows = snapshot.windows
            tokens = snapshot.activity.tokensToday
            requests = snapshot.activity.requestsToday
            credits = snapshot.activity.creditsToday
            balance = snapshot.balance
            totals = snapshot.totals
        }
    }

    private(set) var records: [SourceKey: Record] = [:]
    static let minimumInterval: TimeInterval = 300
    static let maximumInterval: TimeInterval = 1800

    mutating func observe(_ states: [ProviderState], enabled: Set<ProviderID>) {
        let keys = Set(states.filter { enabled.contains($0.provider) }.map(\.id))
        records = records.filter { keys.contains($0.key) }
        for state in states where enabled.contains(state.provider) && !state.isRefreshing {
            guard let attempted = state.lastAttemptAt ?? state.failure?.date ?? state.snapshot?.updatedAt,
                  records[state.id]?.attemptedAt != attempted else { continue }
            let before = records[state.id]
            let content = state.snapshot.map(Content.init)
            records[state.id] = Record(
                attemptedAt: attempted, content: content,
                unchanged: state.failure == nil && before?.content == content ? min(6, (before?.unchanged ?? 0) + 1) : 0,
                failures: state.failure == nil ? 0 : min(4, (before?.failures ?? 0) + 1)
            )
        }
    }

    func dueSources(_ states: [ProviderState], enabled: Set<ProviderID>, at now: Date,
                    conditions: Conditions, afterWake: Bool = false) -> Set<SourceKey> {
        guard conditions.online else { return [] }
        return Set(states.filter { state in
            guard enabled.contains(state.provider), !state.isRefreshing else { return false }
            if let retry = state.failure?.retryAt, retry > now { return false }
            guard let record = records[state.id] else { return true }
            var interval: TimeInterval = record.unchanged >= 3 ? 900 : Self.minimumInterval
            if record.failures > 0 { interval = min(Self.maximumInterval, Self.minimumInterval * pow(2, Double(record.failures))) }
            if state.snapshot?.status == .notInstalled || state.snapshot?.status == .notAuthenticated { interval = Self.maximumInterval }
            if conditions.screenLocked || conditions.lowPower { interval = Self.maximumInterval }
            // Freshen cached/stale quotas and check near a reset, without
            // overriding network failures, energy mode or server cooldowns.
            if record.failures == 0 && !conditions.screenLocked && !conditions.lowPower,
               let snapshot = state.snapshot, snapshot.status == .available {
                if snapshot.isStale(at: now) || snapshot.windows.contains(where: {
                    guard let reset = $0.resetsAt else { return false }
                    return reset.timeIntervalSince(now) < 600
                }) { interval = Self.minimumInterval }
                if afterWake && snapshot.isStale(at: now) { interval = Self.minimumInterval }
            }
            return now.timeIntervalSince(record.attemptedAt) >= interval
        }.map(\.id))
    }
}

/// The OS tells us connectivity, power and lock state. None is transmitted.
@Observable @MainActor
final class RefreshConditions {
    private(set) var online = true
    private(set) var screenLocked = false
    var value: AdaptiveRefreshPolicy.Conditions {
        .init(online: online, screenLocked: screenLocked, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in self?.online = available }
        }
        monitor.start(queue: DispatchQueue(label: "com.usagenow.refresh-connectivity"))
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.screenLocked = locked }
            })
        }
    }
}

@MainActor
final class AdaptiveRefreshScheduler {
    private var task: Task<Void, Never>?
    private var policy = AdaptiveRefreshPolicy()
    private let states: () -> [ProviderState]
    private let enabled: () -> Set<ProviderID>
    private let conditions: () -> AdaptiveRefreshPolicy.Conditions
    private let refresh: (Set<SourceKey>) async -> Void
    private var ticking = false

    init(states: @escaping () -> [ProviderState], enabled: @escaping () -> Set<ProviderID>,
         conditions: @escaping () -> AdaptiveRefreshPolicy.Conditions,
         refresh: @escaping (Set<SourceKey>) async -> Void) {
        self.states = states; self.enabled = enabled; self.conditions = conditions; self.refresh = refresh
    }

    func observe() { policy.observe(states(), enabled: enabled()) }

    func start() {
        stop()
        observe()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func tick(afterWake: Bool = false) async {
        guard !ticking, !Task.isCancelled else { return }
        ticking = true
        defer { ticking = false }
        observe()
        let due = policy.dueSources(states(), enabled: enabled(), at: .now, conditions: conditions(), afterWake: afterWake)
        if !due.isEmpty { await refresh(due); observe() }
    }
}
