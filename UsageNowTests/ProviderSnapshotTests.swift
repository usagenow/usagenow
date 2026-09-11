import Foundation
import Testing
@testable import UsageNow

struct ProviderSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_789_120_800)

    @Test func looksUpWindowsByKind() {
        let snapshot = Fixtures.snapshot(.codex, fiveHour: 74, weekly: 52, at: now)
        #expect(snapshot.window(.fiveHour)?.usage?.displayValue == 74)
        #expect(snapshot.window(.weekly)?.usage?.displayValue == 52)
    }

    @Test func mostCriticalWindowPicksHighestUsage() {
        let snapshot = Fixtures.snapshot(.claudeCode, fiveHour: 43, weekly: 68, at: now)
        #expect(snapshot.mostCriticalWindow?.kind == .weekly)
    }

    @Test func mostCriticalWindowIgnoresUnknownUsage() {
        var snapshot = Fixtures.snapshot(.codex, fiveHour: 20, weekly: 90, at: now)
        snapshot.windows[1].usage = nil
        #expect(snapshot.mostCriticalWindow?.kind == .fiveHour)
    }

    @Test func unavailableSnapshotsHaveNoCriticalWindow() {
        var snapshot = Fixtures.snapshot(.codex, fiveHour: 20, weekly: 90, at: now)
        snapshot.status = .unavailable
        #expect(snapshot.mostCriticalWindow == nil)
    }

    @Test func staleness() {
        let snapshot = Fixtures.snapshot(.codex, fiveHour: 10, weekly: 10, at: now)
        #expect(!snapshot.isStale(at: now.addingTimeInterval(5 * 60)))
        #expect(snapshot.isStale(at: now.addingTimeInterval(18 * 60)))
    }

    @Test func summaryFindsMostCriticalAcrossProviders() {
        let snapshots = [
            Fixtures.snapshot(.codex, fiveHour: 74, weekly: 52, at: now),
            Fixtures.snapshot(.claudeCode, fiveHour: 43, weekly: 88, at: now),
        ]
        let critical = UsageSummary.mostCritical(in: snapshots)
        #expect(critical?.provider == .claudeCode)
        #expect(critical?.window.kind == .weekly)
    }

    @Test func summaryIsEmptyWithoutKnownUsage() {
        #expect(UsageSummary.mostCritical(in: []) == nil)
        #expect(UsageSummary.mostCritical(in: [.notInstalled(.codex, at: now), .unavailable(.claudeCode, at: now)]) == nil)
    }

    @Test func menuBarDisplayModes() {
        let snapshots = [
            Fixtures.snapshot(.codex, fiveHour: 74, weekly: 52, at: now),
            Fixtures.snapshot(.claudeCode, fiveHour: 43, weekly: 88, at: now),
        ]
        #expect(MenuBarDisplayMode.iconOnly.usage(in: snapshots) == nil)
        #expect(MenuBarDisplayMode.mostCriticalPercentage.usage(in: snapshots)?.displayValue == 88)
        #expect(MenuBarDisplayMode.codexPercentage.usage(in: snapshots)?.displayValue == 74)
        #expect(MenuBarDisplayMode.claudePercentage.usage(in: snapshots)?.displayValue == 88)
    }
}
