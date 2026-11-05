import Foundation

enum OverviewPeriod: Int, CaseIterable, Identifiable {
    case today = 1, week = 7, month = 30
    var id: Int { rawValue }
    var title: LocalizedStringResource {
        switch self { case .today: "Today"; case .week: "7 days"; case .month: "30 days" }
    }
}

/// Period selection over the existing local history, without another provider
/// runtime or a second scan. Missing history stays unknown, not a zero total.
struct OverviewReading: Equatable {
    var days: [ActivityHistory.Day] = []
    var metric: ActivityHistory.Metric? = nil
    var tokens: Int64? = nil
    var requests: Int64? = nil
    var credits: Decimal? = nil
    var estimatedCost: Decimal? = nil
    var isCostComplete = true
    var models: [ModelActivity] = []

    init(snapshot: ProviderSnapshot, period: OverviewPeriod, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 1 - period.rawValue, to: today) ?? today
        if let history = snapshot.activity.history {
            days = history.days.filter { $0.start >= start && $0.start <= today }
            guard !days.isEmpty else { return }
            metric = history.metric
            requests = days.reduce(0) { $0 + $1.requests }
            if history.metric == .tokens { tokens = days.reduce(0) { $0 + $1.tokens } }
            if days.contains(where: { $0.credits != nil }) { credits = days.reduce(0) { $0 + ($1.credits ?? 0) } }
            if days.contains(where: { $0.estimatedCost != nil }) {
                estimatedCost = days.reduce(0) { $0 + ($1.estimatedCost ?? 0) }
            }
            isCostComplete = days.allSatisfy(\.isCostComplete)
            models = Self.models(from: days.flatMap(\.models))
        } else if period == .today, calendar.isDate(snapshot.updatedAt, inSameDayAs: now) {
            tokens = snapshot.activity.tokensToday
            requests = snapshot.activity.requestsToday
            credits = snapshot.activity.creditsToday
            estimatedCost = snapshot.activity.estimatedCostToday
            isCostComplete = snapshot.activity.isCostComplete
            models = snapshot.modelActivity
        }
    }

    var hasActivity: Bool { tokens != nil || requests != nil || credits != nil }

    private static func models(from values: [ModelActivity]) -> [ModelActivity] {
        var result: [String: ModelActivity] = [:]
        for model in values {
            guard var old = result[model.id] else { result[model.id] = model; continue }
            old.totalTokens += model.totalTokens
            old.requests += model.requests
            old.isRequestCountKnown = old.isRequestCountKnown && model.isRequestCountKnown
            old.inputTokens = old.inputTokens.flatMap { before in model.inputTokens.map { before + $0 } }
            old.outputTokens = old.outputTokens.flatMap { before in model.outputTokens.map { before + $0 } }
            if old.estimatedCost != nil || model.estimatedCost != nil { old.estimatedCost = (old.estimatedCost ?? 0) + (model.estimatedCost ?? 0) }
            old.lastUsedAt = max(old.lastUsedAt ?? .distantPast, model.lastUsedAt ?? .distantPast)
            result[model.id] = old
        }
        return Array(result.values).sortedByActivity()
    }
}
