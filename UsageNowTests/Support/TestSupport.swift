import Foundation
import Synchronization
@testable import UsageNow

enum Fixtures {
    static func snapshot(
        _ provider: ProviderID,
        fiveHour: Double = 50,
        weekly: Double = 50,
        at date: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            status: .available,
            planName: "Pro",
            windows: [
                UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: fiveHour), resetsAt: date.addingTimeInterval(3600)),
                UsageWindow(kind: .weekly, usage: UsagePercentage(percent: weekly), resetsAt: date.addingTimeInterval(3 * 86_400)),
            ],
            activity: LocalActivity(tokensToday: 1_000_000, requestsToday: 10),
            updatedAt: date
        )
    }
}

/// A provider whose result tests control.
actor StubProvider: UsageProvider {
    nonisolated let id: ProviderID
    private var result: Result<ProviderSnapshot, any Error>
    private let delay: Duration
    private(set) var fetchCount = 0

    init(_ id: ProviderID, _ result: Result<ProviderSnapshot, any Error>, delay: Duration = .zero) {
        self.id = id
        self.result = result
        self.delay = delay
    }

    func setResult(_ result: Result<ProviderSnapshot, any Error>) {
        self.result = result
    }

    private(set) var lastTrigger: RefreshTrigger?

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        lastTrigger = trigger
        fetchCount += 1
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return try result.get()
    }
}

/// A manually advanced clock for time-dependent store logic.
final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ date: Date) {
        current = Mutex(date)
    }

    var now: Date {
        current.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}
