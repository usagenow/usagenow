import Foundation

/// Real OpenCode usage.
///
/// - Activity: tokens, requests, and models from OpenCode's local database
///   (`OpenCodeActivityReader`), today and for the 30-day history.
/// - Quota: none. OpenCode runs on whichever provider the person connects;
///   limits belong to that provider, and OpenCode's own subscriptions show
///   theirs only on its website.
///
/// No credentials are read and nothing leaves the Mac.
struct OpenCodeProvider: UsageProvider {
    let id: ProviderID = .opencode

    private let discover: @Sendable () -> OpenCodeEnvironment
    private let reader: OpenCodeActivityReader
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> OpenCodeEnvironment = { .discover() },
        reader: OpenCodeActivityReader = OpenCodeActivityReader(),
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
        guard environment.isInstalled else { return .notInstalled(.opencode, at: date) }
        // Installed but never used: nothing to read yet.
        guard let database = environment.database else {
            return ProviderSnapshot(provider: .opencode, status: .available, activity: LocalActivity(tokensToday: 0, requestsToday: 0), updatedAt: date)
        }

        let reader = reader
        let period = ActivityPeriod(now: date, calendar: calendar)
        let result: OpenCodeActivityReader.Result
        do {
            result = try await Task.detached(priority: .utility) {
                try reader.activity(database: database, period: period)
            }.value
        } catch {
            // Rethrown so the store keeps the last reading and offers Retry.
            Log.provider.debug("OpenCode's database couldn't be read")
            throw error
        }

        return ProviderSnapshot(
            provider: .opencode,
            status: .available,
            recentModel: result.activity.latestModel,
            activity: LocalActivity(
                tokensToday: result.activity.tokens,
                requestsToday: result.activity.requests,
                estimatedCostToday: result.activity.estimatedCost,
                isCostComplete: result.activity.isCostComplete,
                history: result.history
            ),
            modelActivity: result.activity.models,
            updatedAt: date
        )
    }
}
