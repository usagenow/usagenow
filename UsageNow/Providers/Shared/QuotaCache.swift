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

/// A value a quota source returned, and when.
struct QuotaCacheEntry<Value: Sendable>: Sendable {
    var value: Value
    var fetchedAt: Date
}

extension QuotaCacheEntry: Codable where Value: Codable {}

/// Keeps a cache's last good value somewhere that outlives the process, so
/// quitting, updating, or reinstalling the app doesn't blank the display.
/// Only for usage values — never for credentials.
struct QuotaCacheStore<Value: Sendable>: Sendable {
    var load: @Sendable () -> QuotaCacheEntry<Value>?
    /// `nil` removes the stored value.
    var save: @Sendable (QuotaCacheEntry<Value>?) -> Void
}

extension QuotaCacheStore where Value: Codable {
    /// Stores the entry as JSON under `key`.
    static func userDefaults(_ defaults: UserDefaults = .standard, key: String) -> QuotaCacheStore {
        // UserDefaults is thread-safe, but isn't annotated as Sendable.
        nonisolated(unsafe) let defaults = defaults
        return QuotaCacheStore(
            load: {
                defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(QuotaCacheEntry<Value>.self, from: $0) }
            },
            save: { entry in
                if let entry, let data = try? JSONEncoder().encode(entry) {
                    defaults.set(data, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        )
    }
}

/// Caches a quota source's latest result and limits how often it's queried.
///
/// - At most one request runs at a time; concurrent callers share it.
/// - Automatic refreshes reuse the cached value until `minimumInterval`
///   has passed since the last attempt, successful or not.
/// - Manual refreshes query the source immediately.
/// - After a transient failure, the last good value stays available for
///   `retention`, so the UI can show it as stale instead of dropping it.
///   With a `store`, that includes values from before the app was relaunched.
actor QuotaCache<Value: Sendable> {
    typealias Entry = QuotaCacheEntry<Value>

    let minimumInterval: TimeInterval
    let retention: TimeInterval

    private let store: QuotaCacheStore<Value>?
    private var entry: Entry?
    private var lastAttempt: Date?
    private var inFlight: Task<Void, Never>?

    init(minimumInterval: TimeInterval = 5 * 60, retention: TimeInterval = 60 * 60, store: QuotaCacheStore<Value>? = nil) {
        self.minimumInterval = minimumInterval
        self.retention = retention
        self.store = store
        self.entry = store?.load()
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
        replace(with: nil)
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
            case .value(let value): replace(with: Entry(value: value, fetchedAt: now()))
            case .none: replace(with: nil)
            case .unavailable: break // Keep the last good value; it ages out after `retention`.
            }
        } catch {
            // Keep the previous value; it ages out after `retention`.
            Log.provider.debug("Quota source failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func replace(with newEntry: Entry?) {
        entry = newEntry
        store?.save(newEntry)
    }
}
