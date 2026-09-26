import Foundation

/// Real Qoder usage.
///
/// - Activity: credits spent and model answers, today and for the 30-day
///   history, from the transcripts Qoder's agent writes on this Mac
///   (`QoderSessionReader`).
/// - Quota: none. Qoder shows the plan's remaining credits only in its app
///   and on its website, and keeps no copy on disk UsageNow could read.
///
/// No credentials are read and nothing leaves the Mac.
struct QoderProvider: UsageProvider {
    let id: ProviderID = .qoder

    private let discover: @Sendable () -> QoderEnvironment
    private let sessions = QoderSessionReader()
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> QoderEnvironment = { .discover() },
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
        guard environment.isInstalled else { return .notInstalled(.qoder, at: date) }

        let activity = await sessions.activity(root: environment.sessionsRoot, period: ActivityPeriod(now: date, calendar: calendar))
        return ProviderSnapshot(
            provider: .qoder,
            status: .available,
            activity: LocalActivity(
                requestsToday: activity.requests,
                creditsToday: activity.credits,
                history: activity.history
            ),
            updatedAt: date
        )
    }
}
