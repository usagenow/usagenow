import Foundation
import Testing
@testable import UsageNow

@MainActor
struct VersionOneTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "v1.\(UUID())")! }

    @Test func setupOnlyAppearsOnANewInstallation() {
        let fresh = defaults()
        let setup = FirstRunSetup(defaults: fresh)
        #expect(setup.needsSetup)
        setup.complete()
        #expect(!FirstRunSetup(defaults: fresh).needsSetup)
        let existing = defaults()
        existing.set(["codex"], forKey: "knownProviders")
        #expect(!FirstRunSetup(defaults: existing).needsSetup)
    }

    @Test func notificationMigrationPreservesConsentAndDefaults() {
        let saved = defaults()
        saved.set(true, forKey: "notifiesAboutLimits")
        let preferences = AppPreferences(defaults: saved)
        #expect(preferences.notifiesAboutLimits)
        #expect(preferences.notificationPolicy.rule(for: .codex).thresholds == [20, 5])
        preferences.notificationPolicy.providers["codex"] = .init(enabled: true, warning: 35, critical: 10, resets: false)
        preferences.notificationPolicy.quietHoursEnabled = true
        #expect(AppPreferences(defaults: saved).notificationPolicy == preferences.notificationPolicy)
        #expect(!AppPreferences(defaults: defaults()).notifiesAboutLimits)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ time: String) -> Date { ISO8601DateFormatter().date(from: "2026-10-24T\(time):00Z")! }
    private func reading(_ used: Double, at: Date, reset: Date) -> ProviderSnapshot {
        ProviderSnapshot(provider: .codex, status: .available,
                         windows: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: used), resetsAt: reset)], updatedAt: at)
    }

    @Test func quietHoursCrossMidnightAndRespectLocalTimeZone() {
        var policy = NotificationPolicy()
        policy.quietHoursEnabled = true
        for time in ["22:00", "23:59", "00:00", "07:59"] { #expect(policy.isQuiet(at: date(time), calendar: calendar)) }
        for time in ["08:00", "21:59"] { #expect(!policy.isQuiet(at: date(time), calendar: calendar)) }
        var almaty = calendar
        almaty.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        #expect(policy.isQuiet(at: date("17:00"), calendar: almaty))
        policy.quietStart = 12 * 60; policy.quietEnd = 13 * 60
        #expect(policy.isQuiet(at: date("12:30"), calendar: calendar))
        #expect(!policy.isQuiet(at: date("13:00"), calendar: calendar))
        policy.quietEnd = policy.quietStart
        #expect(!policy.isQuiet(at: date("12:30"), calendar: calendar))
    }

    @Test func quietWarningsAreConsumedAndNeverQueuedForMorning() {
        var policy = NotificationPolicy()
        policy.quietHoursEnabled = true
        var memory: LimitNoticePlanner.Memory = [:]
        let reset = date("15:00")
        let quiet = date("07:59")
        let actions = LimitNoticePlanner.plan(snapshots: [reading(99, at: quiet, reset: reset)], memory: &memory, now: quiet, policy: policy, calendar: calendar)
        #expect(!actions.contains { if case .deliver = $0 { return true }; return false })
        let morning = date("08:01")
        #expect(LimitNoticePlanner.plan(snapshots: [reading(99, at: morning, reset: reset)], memory: &memory, now: morning, policy: policy, calendar: calendar).isEmpty)
    }

    @Test func resetInQuietHoursIsSkippedAfterSleep() {
        var policy = NotificationPolicy()
        policy.quietHoursEnabled = true
        var memory: LimitNoticePlanner.Memory = [:]
        let evening = date("21:00")
        let actions = LimitNoticePlanner.plan(snapshots: [reading(90, at: evening, reset: date("23:00"))], memory: &memory, now: evening, policy: policy, calendar: calendar)
        #expect(actions.count == 1)
        let next = date("08:00").addingTimeInterval(86400)
        #expect(LimitNoticePlanner.plan(snapshots: [reading(1, at: next, reset: next.addingTimeInterval(3600))], memory: &memory, now: next, policy: policy, calendar: calendar).isEmpty)
    }

    @Test func customThresholdsAndStaleLimits() {
        var policy = NotificationPolicy()
        policy.providers["codex"] = .init(enabled: true, warning: 40, critical: 10, resets: false)
        var memory: LimitNoticePlanner.Memory = [:]
        let now = date("12:00")
        let snapshot = reading(65, at: now, reset: date("15:00"))
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot], memory: &memory, now: now, policy: policy).count == 1)
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot], memory: &memory, now: now, policy: policy).isEmpty)
        var other: LimitNoticePlanner.Memory = [:]
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot], memory: &other, now: now.addingTimeInterval(601), policy: policy).isEmpty)
        #expect(LimitNoticePlanner.plan(snapshots: [reading(99, at: now, reset: now)], memory: &other, now: now, policy: policy).isEmpty)
    }

    @Test func cliRetainsUnknownUsageAndDropsPrivateExtraKeys() throws {
        let now = date("12:00")
        let snapshot = WidgetSnapshot(generatedAt: now, state: .providers([
            WidgetProviderSnapshot(provider: .codex, planName: "Pro", modelName: nil,
                                   windows: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 42), resetsAt: now.addingTimeInterval(3600))],
                                   tokensToday: nil, requestsToday: nil, updatedAt: now)
        ]))
        let encoded = try JSONEncoder.widget.encode(snapshot)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["credential"] = "must-never-escape"
        object["path"] = "/private/example-project"
        let data = try JSONSerialization.data(withJSONObject: object)
        let status = try CLIStatus.read(data, now: now)
        #expect(status.schemaVersion == 1)
        #expect(status.providers.first?.windows.first?.remainingPercent == 58)
        #expect(!status.stale)
        let expired = try CLIStatus.read(data, now: now.addingTimeInterval(3601))
        #expect(expired.stale)
        #expect(expired.providers.first?.windows.first?.remainingPercent == nil)
        #expect(expired.providers.first?.stale == true)
        #expect(!status.text.contains("0.0% left"))
        #expect(try status.json().contains("schemaVersion"))
        #expect(try !status.json().contains("must-never-escape"))
        #expect(try !status.json().contains("example-project"))
    }

    @Test func cliRejectsFutureSchemaAndCorruption() {
        #expect(throws: (any Error).self) { try CLIStatus.read(Data("{}".utf8), now: .now) }
        let data = Data(#"{"schemaVersion":2,"generatedAt":"2026-10-24T12:00:00Z","state":{"noProvidersEnabled":{}}}"#.utf8)
        #expect(throws: (any Error).self) { try CLIStatus.read(data, now: .now) }
    }

    @Test func cliInstallationNeverOverwritesAnotherCommand() throws {
        let directory = try TemporaryDirectory()
        try directory.write("helper", text: "executable fixture")
        let helper = directory.url.appending(path: "helper")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let installation = CLIInstallation(helper: helper, link: directory.url.appending(path: "bin/usagenow"))
        try installation.install()
        #expect(installation.isInstalled)
        try installation.remove()
        #expect(!installation.isInstalled)
        #expect(FileManager.default.fileExists(atPath: helper.path))
        try directory.write("bin/usagenow", text: "keep this command")
        let unrelated = directory.url.appending(path: "bin/usagenow")
        #expect(throws: (any Error).self) { try installation.install() }
        #expect(throws: (any Error).self) { try installation.remove() }
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep this command")
    }
}
