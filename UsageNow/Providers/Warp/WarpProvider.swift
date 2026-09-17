import Foundation

/// Real Warp usage.
///
/// - Activity: today's agent requests, credits, and tokens per model, from
///   Warp's local database (`WarpActivityReader`).
/// - Quota: none yet. Warp keeps a request-limit record in its settings, but
///   it still describes the request plan Warp replaced with credits — a limit
///   of 0 — so showing it would be wrong. The section says limits are
///   unavailable instead.
///
/// No credentials are read and nothing leaves the Mac.
struct WarpProvider: UsageProvider {
    let id: ProviderID = .warp

    private let discover: @Sendable () -> WarpEnvironment
    private let reader: WarpActivityReader
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> WarpEnvironment = { .discover() },
        reader: WarpActivityReader = WarpActivityReader(),
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.discover = discover
        self.reader = reader
        self.now = now
        self.calendar = calendar
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.warp, at: date) }
        // Installed but never used: nothing to read yet.
        guard environment.databaseExists else {
            return ProviderSnapshot(provider: .warp, status: .available, activity: LocalActivity(requestsToday: 0, creditsToday: 0), updatedAt: date)
        }

        let reader = reader
        let since = calendar.startOfDay(for: date)
        let result: WarpActivityReader.Result
        do {
            result = try await Task.detached(priority: .utility) {
                try reader.todaysActivity(database: environment.database, since: since)
            }.value
        } catch {
            Log.provider.debug("Warp's database couldn't be read")
            return .unavailable(.warp, at: date)
        }

        return ProviderSnapshot(
            provider: .warp,
            status: .available,
            recentModel: result.latestModel,
            activity: LocalActivity(
                requestsToday: result.requests,
                creditsToday: result.credits,
                isCreditsComplete: result.isCreditsComplete
            ),
            modelActivity: result.models,
            updatedAt: date
        )
    }
}
