import Foundation
import Synchronization

/// Real Claude Code usage.
///
/// - Local activity and model: today's session transcripts.
/// - Plan: the account profile Claude Code caches in its global config.
/// - Quota: only through the experimental `ClaudeUsageLimitsClient`, when
///   the user turned it on. Otherwise no windows are reported.
struct ClaudeCodeProvider: UsageProvider {
    let id: ProviderID = .claudeCode

    private let discover: @Sendable () -> ClaudeCodeEnvironment
    private let sessions = ClaudeSessionReader()
    private let limitsClient: ClaudeUsageLimitsClient?
    private let limitsEnabled: FeatureSwitch
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        discover: @escaping @Sendable () -> ClaudeCodeEnvironment = { .discover() },
        limitsClient: ClaudeUsageLimitsClient? = nil,
        limitsEnabled: FeatureSwitch = FeatureSwitch(false),
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.discover = discover
        self.limitsClient = limitsClient
        self.limitsEnabled = limitsEnabled
        self.now = now
        self.calendar = calendar
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let environment = discover()
        let date = now()
        guard environment.isInstalled else { return .notInstalled(.claudeCode, at: date) }
        guard !environment.configDirectoryExists || environment.configDirectoryIsReadable else {
            return .unavailable(.claudeCode, at: date)
        }

        let profile = ClaudeAccountProfile.read(from: environment.globalConfigFile)
        let activity = await sessions.todaysActivity(roots: environment.sessionRoots, since: calendar.startOfDay(for: date))
        guard profile.isSignedIn || activity.hasSessionFiles else {
            return .notAuthenticated(.claudeCode, at: date)
        }

        var limits: QuotaCache<[UsageWindow]>.Entry?
        if let limitsClient, limitsEnabled.isOn, profile.isSignedIn {
            limits = await limitsClient.windows(trigger: trigger, now: now)
        }
        // A window that reset since it was fetched no longer tells current usage.
        let windows = limits?.value.filter { ($0.resetsAt ?? .distantFuture) > date } ?? []

        return ProviderSnapshot(
            provider: .claudeCode,
            status: .available,
            planName: profile.planName,
            recentModel: activity.activity.latestModel,
            windows: windows,
            activity: LocalActivity(tokensToday: activity.activity.tokens, requestsToday: activity.activity.requests),
            updatedAt: date,
            limitsUpdatedAt: windows.isEmpty ? nil : limits?.fetchedAt
        )
    }
}

/// A thread-safe on/off switch shared between the main actor (which owns
/// preferences) and providers running off it.
final class FeatureSwitch: Sendable {
    private let state: Mutex<Bool>

    init(_ isOn: Bool) {
        state = Mutex(isOn)
    }

    var isOn: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
