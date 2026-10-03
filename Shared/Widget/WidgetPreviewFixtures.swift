#if DEBUG
import Foundation

/// Synthetic widget states for previews and visual checks. Fabricated
/// values only — never data from this Mac.
enum WidgetPreviewFixtures {
    static let now = Date(timeIntervalSince1970: 1_789_128_000)

    static func window(_ kind: UsageWindowKind, usedPercent: Double, resetsIn seconds: TimeInterval) -> UsageWindow {
        UsageWindow(kind: kind, usage: UsagePercentage(percent: usedPercent), resetsAt: now.addingTimeInterval(seconds))
    }

    static let codex = WidgetProviderSnapshot(
        provider: .codex,
        planName: "Plus",
        modelName: "gpt-example-1",
        windows: [window(.weekly, usedPercent: 42, resetsIn: 4 * 86_400)],
        tokensToday: 12_800_000,
        requestsToday: 47,
        recentDays: [0.4, 0.62, 0, 0, 0.55, 0.8, 0.47, 0.71, 0.3, 0, 0.66, 1, 0.58, 0.52]
    )

    static let claude = WidgetProviderSnapshot(
        provider: .claudeCode,
        planName: "Pro",
        modelName: "claude-example-1",
        windows: [
            window(.fiveHour, usedPercent: 34, resetsIn: 3_660),
            window(.weekly, usedPercent: 34, resetsIn: 3 * 86_400),
        ],
        tokensToday: 18_400_000,
        requestsToday: 63
    )

    static let criticalClaude = WidgetProviderSnapshot(
        provider: .claudeCode,
        planName: "Pro",
        modelName: "claude-example-1",
        windows: [
            window(.fiveHour, usedPercent: 89, resetsIn: 3_660),
            window(.weekly, usedPercent: 34, resetsIn: 3 * 86_400),
        ],
        tokensToday: 24_100_000,
        requestsToday: 88
    )

    static let unavailableClaude = WidgetProviderSnapshot(
        provider: .claudeCode,
        planName: "Pro",
        modelName: "claude-example-1",
        windows: [],
        tokensToday: 4_200_000,
        requestsToday: 18,
        quotaUnavailableReason: .signInExpired
    )

    /// Activity only: Gemini CLI reports no usage limits.
    static let gemini = WidgetProviderSnapshot(
        provider: .gemini,
        planName: nil,
        modelName: "gemini-example-1",
        windows: [],
        tokensToday: 1_200_000,
        requestsToday: 24,
        recentDays: [0.2, 0, 0.35, 0.5, 0, 0, 0.9, 0.4, 0.62, 0.3, 0, 0.75, 1, 0.45]
    )

    static func snapshot(_ providers: [WidgetProviderSnapshot], generatedAt: Date = now) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: generatedAt, state: .providers(providers))
    }

    static let normal = snapshot([codex, claude])
    static let critical = snapshot([codex, criticalClaude])
    static let threeProviders = snapshot([codex, criticalClaude, gemini])
    static let codexOnly = snapshot([codex])
    static let geminiOnly = snapshot([gemini])
    static let codexAndGemini = snapshot([codex, gemini])
    static let claudeOnly = snapshot([criticalClaude])
    static let unavailableQuota = snapshot([codex, unavailableClaude])
    static let stale = snapshot([codex, claude], generatedAt: now.addingTimeInterval(-18 * 60))
    static let noProvidersEnabled = WidgetSnapshot(generatedAt: now, state: .noProvidersEnabled)
    static let noProvidersDetected = WidgetSnapshot(generatedAt: now, state: .noProvidersDetected)

    static func entry(_ snapshot: WidgetSnapshot?) -> UsageNowWidgetEntry {
        UsageNowWidgetEntry(date: now, snapshot: snapshot)
    }
}
#endif
