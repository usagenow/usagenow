import Foundation
import Testing
@testable import UsageNow

@MainActor
struct LimitNoticeTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var reset: Date { now.addingTimeInterval(2 * 3600) }

    private func snapshot(_ used: Double?, resetsAt: Date?, provider: ProviderID = .claudeCode) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            status: .available,
            windows: [UsageWindow(kind: .fiveHour, usage: used.flatMap(UsagePercentage.init(percent:)), resetsAt: resetsAt)],
            updatedAt: now
        )
    }

    private func kinds(_ actions: [LimitNoticePlanner.Action]) -> [String] {
        actions.map { action in
            switch action {
            case .deliver(let notice): notice.kind == .reset ? "reset" : "low"
            case .schedule(let notice, _): notice.kind == .reset ? "schedule-reset" : "schedule-low"
            case .cancel: "cancel"
            }
        }
    }

    @Test func staysQuietAboveTheFirstThreshold() {
        var memory: LimitNoticePlanner.Memory = [:]
        let actions = LimitNoticePlanner.plan(snapshots: [snapshot(79, resetsAt: reset)], memory: &memory, now: now)
        #expect(actions.isEmpty)
        #expect(memory.isEmpty)
    }

    @Test func warnsOnceAtEachThresholdAndSchedulesTheReset() {
        var memory: LimitNoticePlanner.Memory = [:]
        #expect(kinds(LimitNoticePlanner.plan(snapshots: [snapshot(80, resetsAt: reset)], memory: &memory, now: now)) == ["low", "schedule-reset"])
        // The same reading, and a slightly worse one, say nothing more.
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot(80, resetsAt: reset)], memory: &memory, now: now).isEmpty)
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot(90, resetsAt: reset)], memory: &memory, now: now).isEmpty)
        #expect(kinds(LimitNoticePlanner.plan(snapshots: [snapshot(96, resetsAt: reset)], memory: &memory, now: now)) == ["low"])
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot(100, resetsAt: reset)], memory: &memory, now: now).isEmpty)
    }

    @Test func aWindowFirstSeenNearlyEmptyGetsOneNotice() {
        var memory: LimitNoticePlanner.Memory = [:]
        let actions = LimitNoticePlanner.plan(snapshots: [snapshot(98, resetsAt: reset)], memory: &memory, now: now)
        #expect(kinds(actions) == ["low", "schedule-reset"])
        #expect(memory.values.first?.notified == 5)
    }

    @Test func aResetTimeReadAFewSecondsOffIsNotRescheduled() {
        var memory: LimitNoticePlanner.Memory = [:]
        _ = LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: reset)], memory: &memory, now: now)
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: reset.addingTimeInterval(12))], memory: &memory, now: now).isEmpty)
        let moved = LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: reset.addingTimeInterval(3600))], memory: &memory, now: now)
        #expect(kinds(moved) == ["schedule-reset"])
    }

    @Test func afterTheScheduledResetTheNextWindowStartsFresh() {
        var memory: LimitNoticePlanner.Memory = [:]
        _ = LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: reset)], memory: &memory, now: now)
        let later = reset.addingTimeInterval(120)
        // The scheduled notice already said it; nothing is sent twice.
        let actions = LimitNoticePlanner.plan(snapshots: [snapshot(2, resetsAt: later.addingTimeInterval(5 * 3600))], memory: &memory, now: later)
        #expect(actions.isEmpty)
        #expect(memory.isEmpty)
        // And the new window warns again when it runs low.
        #expect(kinds(LimitNoticePlanner.plan(snapshots: [snapshot(81, resetsAt: later.addingTimeInterval(5 * 3600))], memory: &memory, now: later)) == ["low", "schedule-reset"])
    }

    @Test func aStaleWindowPastItsResetIsForgotten() {
        var memory: LimitNoticePlanner.Memory = [:]
        _ = LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: reset)], memory: &memory, now: now)
        let later = reset.addingTimeInterval(120)
        let actions = LimitNoticePlanner.plan(snapshots: [snapshot(nil, resetsAt: reset)], memory: &memory, now: later)
        #expect(actions.isEmpty)
        #expect(memory.isEmpty)
    }

    @Test func aLimitWithNoResetTimeSaysSoWhenItRecovers() {
        var memory: LimitNoticePlanner.Memory = [:]
        #expect(kinds(LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: nil, provider: .ollama)], memory: &memory, now: now)) == ["low"])
        #expect(kinds(LimitNoticePlanner.plan(snapshots: [snapshot(3, resetsAt: nil, provider: .ollama)], memory: &memory, now: now)) == ["reset"])
        #expect(memory.isEmpty)
    }

    @Test func anEarlyResetWithdrawsTheScheduledNotice() {
        var memory: LimitNoticePlanner.Memory = [:]
        _ = LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: reset)], memory: &memory, now: now)
        let actions = LimitNoticePlanner.plan(snapshots: [snapshot(0, resetsAt: reset)], memory: &memory, now: now.addingTimeInterval(600))
        #expect(kinds(actions) == ["cancel", "reset"])
    }

    @Test func neverWarnedMeansNoResetNotice() {
        var memory: LimitNoticePlanner.Memory = [:]
        _ = LimitNoticePlanner.plan(snapshots: [snapshot(50, resetsAt: reset)], memory: &memory, now: now)
        let later = reset.addingTimeInterval(120)
        #expect(LimitNoticePlanner.plan(snapshots: [snapshot(0, resetsAt: later.addingTimeInterval(3600))], memory: &memory, now: later).isEmpty)
    }

    @Test func turningAProviderOffWithdrawsItsNotices() {
        var memory: LimitNoticePlanner.Memory = [:]
        _ = LimitNoticePlanner.plan(snapshots: [snapshot(85, resetsAt: reset)], memory: &memory, now: now)
        let actions = LimitNoticePlanner.forget(providersOtherThan: [.codex], memory: &memory)
        #expect(kinds(actions) == ["cancel"])
        #expect(memory.isEmpty)
    }

    @Test func titlesFollowTheRemainingOrUsedSetting() {
        let usage = UsagePercentage(percent: 82)!
        let low = LimitNotice(provider: .claudeCode, window: .fiveHour, scope: nil, kind: .low(usage), resetsAt: reset)
        #expect(low.title(style: .remaining) == "Claude Code: 18% of the 5-hour limit left")
        #expect(low.title(style: .used) == "Claude Code: 82% of the 5-hour limit used")
        #expect(low.body(now: now) == "Resets in 2h 00m")

        let reached = LimitNotice(provider: .codex, window: .weekly, scope: nil, kind: .low(UsagePercentage(percent: 100)!), resetsAt: nil)
        #expect(reached.title(style: .remaining) == "Codex: Weekly limit reached")
        #expect(reached.body(now: now).isEmpty)

        let scoped = LimitNotice(provider: .antigravity, window: .weekly, scope: "Gemini", kind: .reset, resetsAt: nil)
        #expect(scoped.title(style: .used) == "Antigravity: Weekly Gemini limit has reset")
    }

    // MARK: Notifier

    private final class Recorder: LimitNoticeDelivering {
        var delivered: [(identifier: String, title: String, date: Date?)] = []
        var cancelled: [String] = []
        var cancelledAll = 0

        func deliver(identifier: String, title: String, body: String, at date: Date?) {
            delivered.append((identifier, title, date))
        }
        func cancel(identifiers: [String]) { cancelled += identifiers }
        func cancelAll() { cancelledAll += 1 }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "LimitNoticeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func sendsNothingWhileTurnedOff() {
        let recorder = Recorder()
        let notifier = LimitNotifier(defaults: makeDefaults(), delivery: recorder, now: { [now] in now })
        notifier.update(snapshots: [snapshot(99, resetsAt: reset)], enabledProviders: [.claudeCode], style: .remaining)
        #expect(recorder.delivered.isEmpty)
    }

    @Test func remembersAcrossARelaunchWhatItSaid() {
        let defaults = makeDefaults()
        let recorder = Recorder()
        let notifier = LimitNotifier(defaults: defaults, delivery: recorder, now: { [now] in now })
        notifier.setEnabled(true)
        notifier.update(snapshots: [snapshot(85, resetsAt: reset)], enabledProviders: [.claudeCode], style: .remaining)
        #expect(recorder.delivered.map(\.title) == ["Claude Code: 15% of the 5-hour limit left", "Claude Code: 5-hour limit has reset"])
        #expect(recorder.delivered.map(\.date) == [nil, reset])

        let relaunched = LimitNotifier(defaults: defaults, delivery: recorder, now: { [now] in now })
        relaunched.setEnabled(true)
        relaunched.update(snapshots: [snapshot(85, resetsAt: reset)], enabledProviders: [.claudeCode], style: .remaining)
        #expect(recorder.delivered.count == 2)
    }

    @Test func turningOffWithdrawsEverythingAndStartsFresh() {
        let recorder = Recorder()
        let notifier = LimitNotifier(defaults: makeDefaults(), delivery: recorder, now: { [now] in now })
        notifier.setEnabled(true)
        notifier.update(snapshots: [snapshot(85, resetsAt: reset)], enabledProviders: [.claudeCode], style: .remaining)
        notifier.setEnabled(false)
        #expect(recorder.cancelledAll == 1)
        notifier.setEnabled(true)
        notifier.update(snapshots: [snapshot(85, resetsAt: reset)], enabledProviders: [.claudeCode], style: .remaining)
        #expect(recorder.delivered.count == 4)
    }
}
