import Foundation

/// The outcome of asking a quota source for data.
enum QuotaFetchResult<Value: Sendable>: Sendable {
    case value(Value)
    /// This account has no quota to report — for example an API-key
    /// account with no subscription limits. Clears anything cached.
    case none
    /// Quota exists but couldn't be read right now: an expired sign-in,
    /// denied keychain access, or an endpoint that didn't answer. Anything
    /// cached stays, so the UI can show the last known values as stale
    /// rather than showing nothing at all.
    case unavailable
}

/// Caches a quota source's latest result and limits how often it's queried.
///
/// - At most one request runs at a time; concurrent callers share it.
/// - Automatic refreshes reuse the cached value until `minimumInterval`
///   has passed since the last attempt, successful or not.
/// - Manual refreshes query the source immediately.
/// - After a transient failure, the last good value stays available for
///   `retention`, so the UI can show it as stale instead of dropping it.
actor QuotaCache<Value: Sendable> {
    struct Entry: Sendable {
        var value: Value
        var fetchedAt: Date
    }

    let minimumInterval: TimeInterval
    let retention: TimeInterval

    private var entry: Entry?
    private var lastAttempt: Date?
    private var inFlight: Task<Void, Never>?

    init(minimumInterval: TimeInterval = 5 * 60, retention: TimeInterval = 60 * 60) {
        self.minimumInterval = minimumInterval
        self.retention = retention
    }

    func value(
        trigger: RefreshTrigger,
        now: @escaping @Sendable () -> Date,
        fetch: @escaping @Sendable () async throws -> QuotaFetchResult<Value>
    ) async -> Entry? {
        if let inFlight {
            await inFlight.value
        } else if shouldFetch(trigger: trigger, at: now()) {
            let task = Task { await self.run(fetch, now: now) }
            inFlight = task
            await task.value
            inFlight = nil
        }
        guard let entry, now().timeIntervalSince(entry.fetchedAt) <= retention else { return nil }
        return entry
    }

    /// Drops cached data, e.g. when the user turns the source off.
    func clear() {
        entry = nil
        lastAttempt = nil
    }

    private func shouldFetch(trigger: RefreshTrigger, at date: Date) -> Bool {
        guard trigger == .automatic, let lastAttempt else { return true }
        return date.timeIntervalSince(lastAttempt) >= minimumInterval
    }

    private func run(_ fetch: @Sendable () async throws -> QuotaFetchResult<Value>, now: @Sendable () -> Date) async {
        lastAttempt = now()
        do {
            switch try await fetch() {
            case .value(let value): entry = Entry(value: value, fetchedAt: now())
            case .none: entry = nil
            case .unavailable: break // Keep the last good value; it ages out after `retention`.
            }
        } catch {
            // Keep the previous value; it ages out after `retention`.
            Log.provider.debug("Quota source failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}
