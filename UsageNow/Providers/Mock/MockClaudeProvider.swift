import Foundation

/// Mock Claude Code usage. To be replaced by a real `ClaudeCodeProvider`.
struct MockClaudeProvider: UsageProvider {
    static let profile = MockProfile(
        provider: .claudeCode,
        planName: "Max",
        model: "claude-opus-5",
        firstFiveHourReset: 188 * 60,
        weeklyReset: DateComponents(hour: 14, minute: 30, weekday: 3) // Tue 14:30
    )

    let id: ProviderID = .claudeCode
    var scenario: MockScenario
    var latency: Duration
    private let factory: MockSnapshotFactory
    private let now: @Sendable () -> Date

    init(
        scenario: MockScenario = .normal,
        latency: Duration = .milliseconds(800),
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
        case .normal, .loading: MockUsageValues(fiveHourPercent: 43, weeklyPercent: 68, tokensToday: 18_400_000, requestsToday: 63)
        case .high: MockUsageValues(fiveHourPercent: 86, weeklyPercent: 74, tokensToday: 24_100_000, requestsToday: 88)
        case .critical: MockUsageValues(fiveHourPercent: 96, weeklyPercent: 89, tokensToday: 31_200_000, requestsToday: 132)
        case .unavailable, .notInstalled, .notAuthenticated, .failing: nil
        }
    }
}
