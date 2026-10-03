import Foundation

/// Real Cline usage.
///
/// - Activity: tokens, API requests, models, and the cost Cline recorded,
///   today and for the 30-day history, from the tasks the editor extension
///   saves and the sessions the command-line Cline saves on this Mac
///   (`ClineActivityReader`).
/// - Quota: none. Cline runs on whichever provider the person connects;
///   limits belong to that provider.
///
/// No credentials are read and nothing leaves the Mac.
struct ClineProvider: UsageProvider {
    let id: ProviderID = .cline

    private let discover: @Sendable () -> ClineEnvironment
    private let reader = ClineActivityReader()
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> ClineEnvironment = { .discover() },
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.discover = discover
        self.now = now
        self.calendar = calendar
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.cline, at: date) }

        let result = await reader.activity(environment: environment, period: ActivityPeriod(now: date, calendar: calendar))
        return ProviderSnapshot(
            provider: .cline,
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
