import Foundation

/// Mock Codex usage. To be replaced by a real `CodexProvider`.
struct MockCodexProvider: UsageProvider {
    static let profile = MockProfile(
        provider: .codex,
        planName: "Pro",
        model: "gpt-5.6-sol",
        firstFiveHourReset: 84 * 60,
        weeklyReset: DateComponents(hour: 9, minute: 0, weekday: 2) // Mon 09:00
    )

    let id: ProviderID = .codex
    var scenario: MockScenario
    var latency: Duration
    private let factory: MockSnapshotFactory
    private let now: @Sendable () -> Date

    init(
        scenario: MockScenario = .normal,
        latency: Duration = .milliseconds(600),
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.scenario = scenario
        self.latency = latency
        self.factory = MockSnapshotFactory(profile: Self.profile, referenceDate: referenceDate, calendar: calendar)
        self.now = now
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        try await Task.sleep(for: scenario == .loading ? MockSnapshotFactory.loadingLatency : latency)
        return try snapshot()
    }

    /// Builds the snapshot synchronously; used by previews.
    func snapshot() throws -> ProviderSnapshot {
        try factory.snapshot(for: scenario, values: Self.values(for: scenario), now: now())
    }

    static func values(for scenario: MockScenario) -> MockUsageValues? {
        switch scenario {
        case .normal, .loading: MockUsageValues(fiveHourPercent: 74, weeklyPercent: 52, tokensToday: 12_800_000, requestsToday: 47)
        case .high: MockUsageValues(fiveHourPercent: 88, weeklyPercent: 79, tokensToday: 15_600_000, requestsToday: 71)
        case .critical: MockUsageValues(fiveHourPercent: 97, weeklyPercent: 91, tokensToday: 21_300_000, requestsToday: 104)
        case .unavailable, .notInstalled, .notAuthenticated, .failing: nil
        }
    }
}
