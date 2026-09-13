import Foundation

/// Real Gemini CLI usage.
///
/// - Local activity and models: today's session recordings.
/// - Quota: none. Gemini CLI doesn't record usage limits locally, and its
///   quota service needs the Google sign-in, which UsageNow never reads. The
///   card says limits are unavailable rather than estimating them.
/// - Plan: none; Gemini CLI doesn't state one locally.
///
/// UsageNow never reads, refreshes, modifies, or stores Gemini credentials.
struct GeminiProvider: UsageProvider {
    let id: ProviderID = .gemini

    private let discover: @Sendable () -> GeminiEnvironment
    private let sessions = GeminiSessionReader()
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> GeminiEnvironment = { .discover() },
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
        guard environment.isInstalled else { return .notInstalled(.gemini, at: date) }
        guard !environment.homeExists || environment.homeIsReadable else { return .unavailable(.gemini, at: date) }

        let result = await sessions.todaysActivity(roots: environment.sessionRoots, since: calendar.startOfDay(for: date))
        guard environment.isSignedIn || !result.activity.models.isEmpty || result.activity.requests > 0 else {
            return .notAuthenticated(.gemini, at: date)
        }

        return ProviderSnapshot(
            provider: .gemini,
            status: .available,
            recentModel: result.activity.latestModel,
            activity: LocalActivity(tokensToday: result.activity.tokens, requestsToday: result.activity.requests),
            modelActivity: result.activity.models,
            updatedAt: date
        )
    }
}
