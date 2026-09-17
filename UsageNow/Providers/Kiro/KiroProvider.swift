import Foundation

/// Real Kiro usage.
///
/// - Quota: the monthly credit limit Kiro last received, read from the IDE's
///   own log (`KiroUsageLimitsReader`). Kiro refreshes it while it runs;
///   between runs the last reading stays, marked with when it was taken.
/// - Activity: credits and prompt turns today, from session records.
/// - Plan: the subscription title in the same limits answer, e.g. "Free".
///
/// UsageNow makes no request to Kiro's service and reads no Kiro credential.
struct KiroProvider: UsageProvider {
    let id: ProviderID = .kiro

    private let discover: @Sendable () -> KiroEnvironment
    private let readLimits: @Sendable (URL) -> KiroUsageLimits?
    private let sessions = KiroSessionReader()
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> KiroEnvironment = { .discover() },
        readLimits: @escaping @Sendable (URL) -> KiroUsageLimits? = { KiroUsageLimitsReader.latest(in: $0) },
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.discover = discover
        self.readLimits = readLimits
        self.now = now
        self.calendar = calendar
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.kiro, at: date) }

        let limits = readLimits(environment.logsRoot)
        // A reading from before the reset says nothing about the new month.
        let windows = limits.map { [$0.window].asOf(date) } ?? []
        let hasCurrentReading = windows.contains { $0.usage != nil }

        let activity = await sessions.todaysActivity(root: environment.sessionsRoot, since: calendar.startOfDay(for: date))

        return ProviderSnapshot(
            provider: .kiro,
            status: .available,
            planName: limits?.planName,
            windows: windows,
            quotaUnavailableReason: hasCurrentReading ? nil : .toolNotRunning,
            activity: LocalActivity(
                requestsToday: activity.turns,
                creditsToday: activity.credits
            ),
            updatedAt: date,
            limitsUpdatedAt: limits?.observedAt
        )
    }
}
