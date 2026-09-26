import Foundation
import Testing

@testable import UsageNow

@MainActor
struct DiagnosticReportTests {
    private let now = TestDates.noon

    private var environment: DiagnosticReport.Environment {
        var environment = DiagnosticReport.Environment()
        environment.appVersion = "0.6.0"
        environment.build = "4"
        environment.macOS = "Version 26.6.2 (Build 25G100)"
        environment.architecture = "arm64"
        environment.screens = ["1470×919 visible @2x, notch"]
        environment.menuBarManagers = ["Ice"]
        environment.homeDirectory = "/Users/jane"
        return environment
    }

    private let settings = DiagnosticReport.Settings(
        appearance: "system", usageAmountStyle: "remaining", showsActivityHistory: true,
        refreshInterval: "300s", menuBarDisplayMode: "mostCriticalPercentage", fetchClaudeUsageLimits: false
    )

    @Test func describesTheMacSettingsAndProviders() {
        var codex = ProviderState(provider: .codex)
        codex.snapshot = ProviderSnapshot(
            provider: .codex,
            status: .available,
            planName: "Plus",
            windows: [UsageWindow(kind: .weekly, usage: UsagePercentage(percent: 42), resetsAt: now.addingTimeInterval(3 * 86_400))],
            activity: LocalActivity(tokensToday: 1_000, requestsToday: 2),
            updatedAt: now.addingTimeInterval(-120)
        )
        let report = DiagnosticReport.make(
            states: [codex], order: [.codex, .deepseek], enabled: [.codex, .deepseek],
            hasAPIKey: { _ in true }, settings: settings, environment: environment, now: now
        )
        #expect(report.contains("UsageNow 0.6.0 (4)"))
        #expect(report.contains("notch"))
        #expect(report.contains("Menu bar managers running: Ice"))
        #expect(report.contains("- Codex: available; plan Plus; weekly 42% used, resets in 3d"))
        #expect(report.contains("updated 2m ago"))
        #expect(report.contains("- DeepSeek: API key saved; no reading yet"))
        #expect(report.contains("Turned off:"))
    }

    /// Error text can quote paths, emails, or tokens; none survive.
    @Test func errorMessagesAreCleaned() {
        var claude = ProviderState(provider: .claudeCode)
        claude.failure = RefreshFailure(
            message: "Couldn't read /Users/jane/.claude/projects/x.jsonl for jane@example.com with token sk-ant-oat01-AbCdEfGhIjKlMnOpQrStUvWxYz0123",
            date: now.addingTimeInterval(-30)
        )
        let report = DiagnosticReport.make(
            states: [claude], order: [.claudeCode], enabled: [.claudeCode],
            hasAPIKey: { _ in false }, settings: settings, environment: environment, now: now
        )
        #expect(report.contains("~/.claude/projects/x.jsonl"))
        #expect(!report.contains("jane"))
        #expect(!report.contains("AbCdEfGhIjKlMnOpQrStUvWxYz"))
        #expect(report.contains("<email>"))
        #expect(report.contains("<redacted>"))
    }

    @Test func otherUsersFoldersAreHiddenToo() {
        #expect(DiagnosticReport.sanitized("at /Users/bob/Library", homeDirectory: "/Users/jane") == "at /Users/…/Library")
    }

    @Test func agesAreRelative() {
        #expect(DiagnosticReport.age(of: now.addingTimeInterval(-90), now: now) == "1m ago")
        #expect(DiagnosticReport.age(of: now.addingTimeInterval(7200), now: now) == "in 2h")
    }
}
