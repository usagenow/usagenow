import Foundation
import SQLite3
import Testing

@testable import UsageNow

/// A throwaway settings database shaped like the one Windsurf keeps.
private final class WindsurfFixtureDatabase {
    let url: URL
    private let directory: TemporaryDirectory
    private var handle: OpaquePointer?

    init() throws {
        directory = try TemporaryDirectory()
        url = directory.url.appending(path: "state.vscdb")
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        guard sqlite3_exec(handle, "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)", nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    deinit { sqlite3_close(handle) }

    func set(_ key: String, _ value: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT INTO ItemTable (key, value) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
    }
}

struct WindsurfProviderTests {
    /// 2026-10-06 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_288_000)

    private func provider(_ database: WindsurfFixtureDatabase?, installed: Bool = true) -> WindsurfProvider {
        let url = database?.url
        let now = now
        return WindsurfProvider(
            discover: {
                WindsurfEnvironment(
                    database: url ?? URL(filePath: "/nonexistent/state.vscdb"),
                    databaseExists: url != nil,
                    application: installed ? URL(filePath: "/Applications/Windsurf.app") : nil
                )
            },
            now: { now }
        )
    }

    @Test func readsDailyAndWeeklyQuotasLeft() async throws {
        let db = try WindsurfFixtureDatabase()
        try db.set("windsurfAuthStatus", #"{"apiKey":"secret"}"#)
        try db.set(WindsurfPlanReader.key, """
            {"planName":"Pro","quotaUsage":{"dailyRemainingPercent":9,"weeklyRemainingPercent":54,
             "dailyResetAtUnix":1791331200,"weeklyResetAtUnix":1791763200}}
            """)

        let snapshot = try await provider(db).fetchSnapshot(trigger: .manual)

        #expect(snapshot.planName == "Pro")
        #expect(snapshot.quotaUnavailableReason == nil)
        #expect(snapshot.windows.map(\.kind) == [.custom(minutes: 1440), .weekly])
        #expect(snapshot.windows.map(\.usage) == [UsagePercentage(percent: 91), UsagePercentage(percent: 46)])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_791_331_200))
        #expect(UsageWindowKind.custom(minutes: 1440).title == "Daily")
    }

    @Test func fallsBackToTheBillingCyclesCredits() async throws {
        let db = try WindsurfFixtureDatabase()
        try db.set(WindsurfPlanReader.key, """
            {"planName":"Pro","endTimestamp":1792000000000,
             "usage":{"messages":500,"remainingMessages":125,"flowActions":1500,"usedFlowActions":0}}
            """)

        let snapshot = try await provider(db).fetchSnapshot(trigger: .manual)

        #expect(snapshot.windows.map(\.kind) == [.monthly, .monthly])
        #expect(snapshot.windows.map(\.scope) == [nil, "Flow actions"])
        #expect(snapshot.windows.map(\.usage) == [UsagePercentage(percent: 75), UsagePercentage(percent: 0)])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_792_000_000))
    }

    @Test func malformedRemainingCountsCannotOverflow() throws {
        let plan = try JSONDecoder().decode(WindsurfPlanReader.PlanInfo.self, from: Data("""
            {"usage":{"messages":9223372036854775807,"remainingMessages":-9223372036854775808,
                      "flowActions":100,"remainingFlowActions":9223372036854775807}}
            """.utf8))
        #expect(plan.windows.map(\.usage) == [UsagePercentage(percent: 100), UsagePercentage(percent: 0)])
    }

    @Test func aQuotaThatHasResetSinceIsUnknown() async throws {
        let db = try WindsurfFixtureDatabase()
        try db.set(WindsurfPlanReader.key, """
            {"quotaUsage":{"dailyRemainingPercent":0,"weeklyRemainingPercent":40,
             "dailyResetAtUnix":1791200000,"weeklyResetAtUnix":1791763200}}
            """)

        let snapshot = try await provider(db).fetchSnapshot(trigger: .manual)

        #expect(snapshot.windows[0].usage == nil, "The day reset after Windsurf last cached it")
        #expect(snapshot.windows[1].usage == UsagePercentage(percent: 60))
    }

    @Test func withoutACachedPlanAsksToOpenWindsurf() async throws {
        // Kept in a constant so the database outlives the read.
        let emptyDatabase = try WindsurfFixtureDatabase()
        let empty = try await provider(emptyDatabase).fetchSnapshot(trigger: .manual)
        #expect(empty.windows.isEmpty)
        #expect(empty.quotaUnavailableReason == .toolNotRunning)

        let db = try WindsurfFixtureDatabase()
        try db.set(WindsurfPlanReader.key, #"{"planName":"Free"}"#)
        let free = try await provider(db).fetchSnapshot(trigger: .manual)
        #expect(free.planName == "Free")
        #expect(free.quotaUnavailableReason == .toolNotRunning)

        let neverOpened = try await provider(nil).fetchSnapshot(trigger: .manual)
        #expect(neverOpened.status == .available)
        #expect(neverOpened.windows.isEmpty)
    }

    @Test func anUnreadableCacheIsLeftOut() async throws {
        let db = try WindsurfFixtureDatabase()
        try db.set(WindsurfPlanReader.key, "not json")
        let snapshot = try await provider(db).fetchSnapshot(trigger: .manual)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.planName == nil)
    }

    @Test func notInstalledWithoutTheAppOrItsDatabase() async throws {
        let snapshot = try await provider(nil, installed: false).fetchSnapshot(trigger: .manual)
        #expect(snapshot.status == .notInstalled)
    }
}
