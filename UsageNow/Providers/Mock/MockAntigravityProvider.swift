import Foundation

/// Mock Antigravity usage: weekly limits shared by model groups, and no
/// local activity — like the real provider with limits turned on.
struct MockAntigravityProvider: UsageProvider {
    let id: ProviderID = .antigravity
    var scenario: MockScenario
    var latency: Duration
    private let now: @Sendable () -> Date

    init(scenario: MockScenario = .normal, latency: Duration = .milliseconds(800), now: @escaping @Sendable () -> Date = { .now }) {
        self.scenario = scenario
        self.latency = latency
        self.now = now
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        try await Task.sleep(for: scenario == .loading ? MockSnapshotFactory.loadingLatency : latency)
        return try snapshot()
    }

    func snapshot() throws -> ProviderSnapshot {
        let date = now()
        let used: (gemini: Double, claudeAndGPT: Double)
        switch scenario {
        case .normal, .loading: used = (12, 30)
        case .high: used = (55, 81)
        case .critical: used = (70, 97)
        case .unavailable:
            return ProviderSnapshot(provider: .antigravity, status: .available, quotaUnavailableReason: .signInExpired, updatedAt: date)
        case .notInstalled: return .notInstalled(.antigravity, at: date)
        case .notAuthenticated: return .notAuthenticated(.antigravity, at: date)
        case .failing: throw ProviderError.refreshFailed(reason: "The mock Antigravity provider is set to fail.")
        }
        let reset = date.addingTimeInterval(4 * 24 * 3_600)
        return ProviderSnapshot(
            provider: .antigravity,
            status: .available,
            windows: [
                UsageWindow(kind: .weekly, scope: "Gemini", usage: UsagePercentage(percent: used.gemini), resetsAt: reset),
                UsageWindow(kind: .weekly, scope: "Claude and GPT", usage: UsagePercentage(percent: used.claudeAndGPT), resetsAt: reset),
            ],
            updatedAt: date
        )
    }
}
