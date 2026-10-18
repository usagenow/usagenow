import Foundation

/// Real Antigravity usage.
///
/// - Quota: asked of the Antigravity app's language server while the app runs,
///   or the official read-only CLI report when the IDE cannot answer.
///   Antigravity's limits are shared by groups of
///   models, so each group's bucket becomes a scoped window. Between runs, the
///   last limits stay for a day, marked stale.
/// - Activity: none. Antigravity stores conversations in an undocumented binary
///   format, and UsageNow doesn't guess at token counts.
///
/// No credentials are read or sent.
struct AntigravityProvider: UsageProvider {
    let id: ProviderID = .antigravity

    private let discover: @Sendable () -> AntigravityEnvironment
    private let server: AntigravityLocalServer
    private let cli: AntigravityCLI
    private let now: @Sendable () -> Date

    init(
        discover: @escaping @Sendable () -> AntigravityEnvironment = { .discover() },
        server: AntigravityLocalServer = AntigravityLocalServer(),
        cli: AntigravityCLI = AntigravityCLI(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.discover = discover
        self.server = server
        self.cli = cli
        self.now = now
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.antigravity, at: date) }

        let limits = await server.windows(trigger: trigger, now: now)
        let reachability = await server.reachability
        if reachability != .running, let executable = environment.executable {
            let report = await cli.windows(executable: executable, trigger: trigger, now: now)
            let cliAvailable = await cli.available
            if let report, cliAvailable || report.fetchedAt > (limits?.fetchedAt ?? .distantPast) {
                let windows = report.value.asOf(date)
                // Do not attach a tier from the IDE: the CLI may be signed
                // into a different account. The report has no plan field.
                return ProviderSnapshot(provider: .antigravity, status: .available, windows: windows,
                    quotaUnavailableReason: cliAvailable ? (windows.contains(where: { $0.usage != nil }) ? nil : .temporarilyUnavailable) : .toolNotRunning,
                    updatedAt: date, limitsUpdatedAt: report.fetchedAt)
            }
        }
        let windows = limits?.value.asOf(date) ?? []
        let hasCurrentReading = windows.contains { $0.usage != nil && ($0.resetsAt ?? .distantFuture) > date }

        return ProviderSnapshot(
            provider: .antigravity,
            status: .available,
            planName: await server.tierName.map(AntigravityUserStatus.displayName),
            windows: windows,
            quotaUnavailableReason: Self.reason(reachability: reachability, hasCurrentReading: hasCurrentReading),
            updatedAt: date,
            limitsUpdatedAt: windows.isEmpty ? nil : limits?.fetchedAt
        )
    }

    private static func reason(reachability: AntigravityLocalServer.Reachability, hasCurrentReading: Bool) -> QuotaUnavailableReason? {
        switch reachability {
        case .running: hasCurrentReading ? nil : .temporarilyUnavailable
        case .unusableAnswer: .temporarilyUnavailable
        case .notRunning, .unknown: .toolNotRunning
        }
    }
}
