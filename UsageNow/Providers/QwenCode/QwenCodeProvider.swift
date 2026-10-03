import Foundation

/// Real Qwen Code usage.
///
/// - Activity: tokens, answers, and models, today and for the 30-day
///   history, from the session recordings Qwen Code writes on this Mac
///   (`QwenCodeSessionReader`).
/// - Quota: none. Qwen Code records no limits on disk.
///
/// No credentials are read and nothing leaves the Mac.
struct QwenCodeProvider: UsageProvider {
    let id: ProviderID = .qwen

    private let discover: @Sendable () -> QwenCodeEnvironment
    private let sessions = QwenCodeSessionReader()
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> QwenCodeEnvironment = { .discover() },
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
        guard environment.isInstalled else { return .notInstalled(.qwen, at: date) }

        let result = await sessions.activity(root: environment.sessionsRoot, period: ActivityPeriod(now: date, calendar: calendar))
        return ProviderSnapshot(
            provider: .qwen,
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
