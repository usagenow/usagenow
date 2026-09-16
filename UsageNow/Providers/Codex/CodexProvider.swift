import Foundation

/// Real Codex usage.
///
/// - Quota: the official `codex app-server` (`account/rateLimits/read`),
///   cached for 5 minutes between automatic refreshes. Session files also
///   record rate limits after every Codex response; whichever source is
///   newer wins, and session records are the fallback when the app-server
///   is unavailable (shown as stale via `limitsUpdatedAt`).
/// - Local activity: today's `token_usage_record` entries in session files.
/// - Model: the latest `turn_context` in today's sessions.
/// - Plan: the `planType` reported alongside rate limits.
struct CodexProvider: UsageProvider {
    typealias AppServerFetch = @Sendable (CodexEnvironment) async throws -> CodexAppServerClient.Outcome

    let id: ProviderID = .codex

    private let discover: @Sendable () -> CodexEnvironment
    private let appServer: AppServerFetch?
    private let sessions = CodexSessionReader()
    private let quota = QuotaCache<CodexAppServerClient.Outcome>()
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    /// - Parameter appServer: Queries the app-server. `nil` disables it (tests).
    init(
        discover: @escaping @Sendable () -> CodexEnvironment = { .discover() },
        appServer: AppServerFetch? = CodexProvider.liveAppServer,
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.discover = discover
        self.appServer = appServer
        self.now = now
        self.calendar = calendar
    }

    static let liveAppServer: AppServerFetch = { environment in
        guard let executable = environment.executable else {
            throw CodexAppServerClient.ClientError.launchFailed
        }
        return try await CodexAppServerClient(executable: executable, codexHome: environment.home).fetch()
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.codex, at: date) }
        guard !environment.homeExists || environment.homeIsReadable else { return .unavailable(.codex, at: date) }

        let since = calendar.startOfDay(for: date)
        async let local = sessions.todaysActivity(roots: environment.sessionRoots, since: since)
        let server = await serverOutcome(environment: environment, trigger: trigger)
        let activity = await local

        switch server?.value {
        case .notSignedIn:
            return .notAuthenticated(.codex, at: date)
        case nil where !environment.hasAuthFile && !activity.hasSessionFiles && environment.executable != nil:
            // No credentials file, no activity, and no answer from the app-server.
            return .notAuthenticated(.codex, at: date)
        default:
            break
        }

        let limits = await rateLimits(server: server, local: activity, environment: environment)
        return ProviderSnapshot(
            provider: .codex,
            status: .available,
            planName: CodexPlan.displayName(for: limits?.planType ?? server?.value.accountPlanType),
            recentModel: activity.activity.latestModel,
            windows: limits?.usageWindows(at: date) ?? [],
            activity: LocalActivity(
                tokensToday: activity.activity.tokens,
                requestsToday: activity.activity.requests,
                estimatedCostToday: activity.activity.estimatedCost,
                isCostComplete: activity.activity.isCostComplete
            ),
            modelActivity: activity.activity.models,
            updatedAt: date,
            limitsUpdatedAt: limits?.capturedAt
        )
    }

    private func serverOutcome(environment: CodexEnvironment, trigger: RefreshTrigger) async -> QuotaCache<CodexAppServerClient.Outcome>.Entry? {
        guard let appServer, environment.executable != nil else { return nil }
        return await quota.value(trigger: trigger, now: now) {
            .value(try await appServer(environment))
        }
    }

    /// The newest rate limits from the app-server or session records.
    private func rateLimits(
        server: QuotaCache<CodexAppServerClient.Outcome>.Entry?,
        local: CodexSessionReader.Result,
        environment: CodexEnvironment
    ) async -> CodexRateLimitSnapshot? {
        var candidates: [CodexRateLimitSnapshot] = []
        switch server?.value {
        case .rateLimits(let snapshot):
            candidates.append(snapshot)
        case .noSubscriptionLimits:
            return nil
        case .signedInWithoutRateLimits, .notSignedIn, nil:
            break
        }
        if let recorded = local.latestRateLimits {
            candidates.append(recorded)
        }
        if candidates.isEmpty, let recorded = sessions.latestRecordedRateLimits(roots: environment.sessionRoots) {
            candidates.append(recorded)
        }
        return candidates.max { $0.capturedAt < $1.capturedAt }
    }
}
