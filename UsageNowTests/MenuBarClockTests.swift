import Foundation
import Testing
@testable import UsageNow

@MainActor
struct MenuBarClockTests {
    @Test func inactiveClockDoesNotRunAndRepeatedActivationDoesNotRestartIt() {
        let clock = MenuBarClock(now: .distantPast)
        #expect(!clock.isRunning)
        #expect(clock.now == .distantPast)
        clock.setActive(true)
        defer { clock.setActive(false) }
        let started = clock.now
        #expect(clock.isRunning)
        #expect(started > .distantPast)
        for _ in 0..<100 { clock.setActive(true) }
        #expect(clock.now == started)
        clock.setActive(false)
        #expect(!clock.isRunning)
    }

    @Test func clockTicksThenStopsWithoutLateUpdates() async throws {
        let clock = MenuBarClock(interval: .milliseconds(10))
        clock.setActive(true)
        defer { clock.setActive(false) }
        let initial = clock.now
        for _ in 0..<100 {
            if clock.now > initial { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(clock.now > initial)
        clock.setActive(false)
        let stopped = clock.now
        try await Task.sleep(for: .milliseconds(50))
        #expect(clock.now == stopped)
        #expect(!clock.isRunning)
    }

    @Test func activeClockDoesNotKeepItsOwnerAlive() async throws {
        weak var released: MenuBarClock?
        do {
            let clock = MenuBarClock(interval: .milliseconds(10))
            released = clock
            clock.setActive(true)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(released == nil)
    }
}
