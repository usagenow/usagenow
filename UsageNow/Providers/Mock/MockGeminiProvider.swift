import Foundation

/// Mock Gemini CLI usage: activity by model, and no usage limits — like the real provider.
struct MockGeminiProvider: UsageProvider {
    static let profile = MockProfile(
        provider: .gemini,
        planName: nil,
        model: "gemini-3.1-pro",
        secondaryModel: "gemini-3.5-flash",
        reportsLimits: false,
        firstFiveHourReset: 188 * 60,
        weeklyReset: DateComponents(hour: 14, minute: 30, weekday: 3) // Tue 14:30
    )

    let id: ProviderID = .gemini
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
        case .normal, .loading: MockUsageValues(fiveHourPercent: 0, weeklyPercent: 0, tokensToday: 1_200_000, requestsToday: 24)
        case .high: MockUsageValues(fiveHourPercent: 0, weeklyPercent: 0, tokensToday: 6_800_000, requestsToday: 96)
        case .critical: MockUsageValues(fiveHourPercent: 0, weeklyPercent: 0, tokensToday: 14_300_000, requestsToday: 188)
        case .unavailable, .notInstalled, .notAuthenticated, .failing: nil
        }
    }
}
