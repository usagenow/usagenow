import Foundation

/// Real Windsurf usage.
///
/// - Quota: the daily and weekly limits — or, on older plans, the billing
///   cycle's prompt credits — that Windsurf last cached in its settings
///   database (`WindsurfPlanReader`). Windsurf updates the cache while it
///   runs; a window that has reset since shows as unknown.
/// - Plan: the plan name in the same cache, e.g. "Pro".
///
/// UsageNow makes no request to Windsurf's service and reads no Windsurf
/// credential. Windsurf records no per-request activity on the Mac, so
/// there's none to show.
struct WindsurfProvider: UsageProvider {
    let id: ProviderID = .windsurf

    private let discover: @Sendable () -> WindsurfEnvironment
    private let reader: WindsurfPlanReader
    private let now: @Sendable () -> Date

    init(
        discover: @escaping @Sendable () -> WindsurfEnvironment = { .discover() },
        reader: WindsurfPlanReader = WindsurfPlanReader(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.discover = discover
        self.reader = reader
        self.now = now
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.windsurf, at: date) }

        var plan: WindsurfPlanReader.PlanInfo?
        if environment.databaseExists {
            let reader = reader
            do {
                plan = try await Task.detached(priority: .utility) {
                    try reader.plan(database: environment.database)
                }.value
            } catch {
                // Rethrown so the store keeps the last reading and offers Retry.
                Log.provider.debug("Windsurf's database couldn't be read")
                throw error
            }
        }

        let windows = plan?.windows.asOf(date) ?? []
        return ProviderSnapshot(
            provider: .windsurf,
            status: .available,
            planName: plan?.planName,
            windows: windows,
            // Windsurf caches its limits when it runs; until then there are none.
            quotaUnavailableReason: windows.contains { $0.usage != nil } ? nil : .toolNotRunning,
            updatedAt: date
        )
    }
}
