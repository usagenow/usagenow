import Foundation

/// Deterministic canned states for mock providers, used by previews, tests
/// and manual QA. Production runs real providers unless one of these is
/// requested at launch, for example:
/// `-UsageNowMockCodex critical -UsageNowMockClaude failing`
enum MockScenario: String, Sendable, CaseIterable {
    case normal
    case high
    case critical
    /// Signed in, but quota can't be determined.
    case unavailable
    case notInstalled
    case notAuthenticated
    /// Every refresh throws.
    case failing
    /// Refresh never finishes in practice.
    case loading
}

/// Usage values for one mock scenario.
struct MockUsageValues: Sendable {
    var fiveHourPercent: Double
    var weeklyPercent: Double
    var tokensToday: Int64
    var requestsToday: Int64
}

/// Fixed characteristics of a mocked provider.
struct MockProfile: Sendable {
    var provider: ProviderID
    var planName: String?
    var model: String
    /// A second model that takes a smaller share of the activity.
    var secondaryModel: String? = nil
    /// `false` for providers that report activity but no usage limits.
    var reportsLimits = true
    /// Time from the reference date until the first 5-hour reset.
    var firstFiveHourReset: TimeInterval
    /// Weekday (1 = Sunday), hour and minute of the weekly reset.
    var weeklyReset: DateComponents
}

/// Builds mock snapshots with reset dates that tick down naturally
/// between refreshes instead of jumping back on every fetch.
struct MockSnapshotFactory: Sendable {
    static let fiveHours: TimeInterval = 5 * 60 * 60
    static let loadingLatency: Duration = .seconds(3600)

    var profile: MockProfile
    var referenceDate: Date
    var calendar: Calendar

    func snapshot(for scenario: MockScenario, values: MockUsageValues?, now: Date) throws -> ProviderSnapshot {
        switch scenario {
        case .notInstalled:
            return .notInstalled(profile.provider, at: now)
        case .notAuthenticated:
            return .notAuthenticated(profile.provider, at: now)
        case .unavailable:
            return ProviderSnapshot(
                provider: profile.provider,
                status: .available,
                planName: profile.planName,
                recentModel: profile.model,
                activity: LocalActivity(tokensToday: 4_200_000, requestsToday: 18),
                modelActivity: modelActivity(tokens: 4_200_000, requests: 18, now: now),
                updatedAt: now
            )
        case .failing:
            throw ProviderError.refreshFailed(reason: "The mock \(profile.provider.displayName) provider is set to fail.")
        case .normal, .high, .critical, .loading:
            guard let values else { return .unavailable(profile.provider, at: now) }
            return ProviderSnapshot(
                provider: profile.provider,
                status: .available,
                planName: profile.planName,
                recentModel: profile.model,
                windows: !profile.reportsLimits ? [] : [
                    UsageWindow(
                        kind: .fiveHour,
                        usage: UsagePercentage(percent: values.fiveHourPercent),
                        resetsAt: nextFiveHourReset(after: now)
                    ),
                    UsageWindow(
                        kind: .weekly,
                        usage: UsagePercentage(percent: values.weeklyPercent),
                        resetsAt: nextWeeklyReset(after: now)
                    ),
                ],
                activity: LocalActivity(tokensToday: values.tokensToday, requestsToday: values.requestsToday),
                modelActivity: modelActivity(tokens: values.tokensToday, requests: values.requestsToday, now: now),
                updatedAt: now
            )
        }
    }

    /// Splits activity between the profile's models, roughly four to one.
    func modelActivity(tokens: Int64, requests: Int64, now: Date) -> [ModelActivity] {
        guard let secondary = profile.secondaryModel else {
            return [ModelActivity(modelID: profile.model, totalTokens: tokens, requests: requests, lastUsedAt: now)]
        }
        let secondaryTokens = tokens / 5
        let secondaryRequests = requests / 5
        return [
            ModelActivity(modelID: profile.model, totalTokens: tokens - secondaryTokens, requests: requests - secondaryRequests, lastUsedAt: now),
            ModelActivity(modelID: secondary, totalTokens: secondaryTokens, requests: secondaryRequests, lastUsedAt: now.addingTimeInterval(-40 * 60)),
        ].sortedByActivity()
    }

    /// The first reset after `now` in a rolling 5-hour cycle anchored at the reference date.
    func nextFiveHourReset(after now: Date) -> Date {
        let first = referenceDate.addingTimeInterval(profile.firstFiveHourReset)
        guard now >= first else { return first }
        let elapsedCycles = (now.timeIntervalSince(first) / Self.fiveHours).rounded(.down) + 1
        return first.addingTimeInterval(elapsedCycles * Self.fiveHours)
    }

    func nextWeeklyReset(after now: Date) -> Date {
        calendar.nextDate(after: now, matching: profile.weeklyReset, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(7 * 24 * 60 * 60)
    }
}
