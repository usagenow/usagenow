import Foundation

/// Real Grok Build usage.
///
/// - Activity: tokens, model calls, models, and the cost xAI reported, today
///   and for the 30-day history, from the session logs Grok Build writes on
///   this Mac (`GrokBuildSessionReader`).
/// - Quota: none. A Grok plan's weekly usage is shown only in the account's
///   settings on the web, and Grok Build keeps no copy on disk.
///
/// No credentials are read and nothing leaves the Mac.
struct GrokBuildProvider: UsageProvider {
    let id: ProviderID = .grok

    private let discover: @Sendable () -> GrokBuildEnvironment
    private let sessions = GrokBuildSessionReader()
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> GrokBuildEnvironment = { .discover() },
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
        guard environment.isInstalled else { return .notInstalled(.grok, at: date) }

        let result = await sessions.activity(root: environment.sessionsRoot, period: ActivityPeriod(now: date, calendar: calendar))
        return ProviderSnapshot(
            provider: .grok,
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
