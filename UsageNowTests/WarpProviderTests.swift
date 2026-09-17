import Foundation
import SQLite3
import Testing

@testable import UsageNow

/// A throwaway database with the columns Warp 2026 has, filled with fixtures.
private final class WarpFixtureDatabase {
    let url: URL
    private let directory: TemporaryDirectory
    private var handle: OpaquePointer?

    init() throws {
        directory = try TemporaryDirectory()
        url = directory.url.appending(path: "warp.sqlite")
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        try execute("""
            CREATE TABLE ai_queries (id INTEGER PRIMARY KEY, exchange_id TEXT, conversation_id TEXT, start_ts DATETIME,
                input TEXT, working_directory TEXT, output_status TEXT, model_id TEXT, planning_model_id TEXT, coding_model_id TEXT);
            CREATE TABLE agent_conversations (id INTEGER PRIMARY KEY, conversation_id TEXT, conversation_data TEXT,
                last_modified_at TIMESTAMP, summary TEXT);
            """)
    }

    deinit { sqlite3_close(handle) }

    func query(_ conversation: String, at timestamp: String, status: String = #""Completed""#) throws {
        try execute(
            "INSERT INTO ai_queries (conversation_id, start_ts, input, output_status, model_id) VALUES (?, ?, ?, ?, 'auto')",
            [conversation, timestamp, "please read ~/secret.txt and usage_metadata credits_spent 999", status]
        )
    }

    func conversation(_ id: String, modified: String, credits: Double?, tokens: String = "[]") throws {
        let creditsField = credits.map { #","credits_spent":\#($0)"# } ?? ""
        let data = #"{"server_conversation_token":"tok","messages":[{"text":"credits_spent 500"}],"conversation_usage_metadata":{"was_summarized":false\#(creditsField),"token_usage":\#(tokens)}}"#
        try execute("INSERT INTO agent_conversations (conversation_id, conversation_data, last_modified_at) VALUES (?, ?, ?)", [id, data, modified])
    }

    private func execute(_ sql: String, _ values: [String] = []) throws {
        if values.isEmpty {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
            return
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
    }
}

struct WarpActivityReaderTests {
    /// 2026-09-17 00:00 UTC.
    private let midnight = Date(timeIntervalSince1970: 1_789_603_200)

    @Test func countsTodaysAnsweredRequests() throws {
        let db = try WarpFixtureDatabase()
        try db.query("c1", at: "2026-09-16 23:59:59.900000")
        try db.query("c1", at: "2026-09-17 08:00:00.100000")
        try db.query("c2", at: "2026-09-17 09:00:00.000000", status: #""Cancelled""#)
        try db.query("c2", at: "2026-09-17 09:05:00.000000", status: #""Failed""#)
        try db.query("c2", at: "2026-09-17 09:06:00.000000", status: #""Pending""#)

        let result = try WarpActivityReader().todaysActivity(database: db.url, since: midnight)
        #expect(result.requests == 2)
    }

    @Test func countsCreditsAndModelsOfConversationsThatBeganToday() throws {
        let db = try WarpFixtureDatabase()
        try db.query("new", at: "2026-09-17 10:00:00.000000")
        try db.conversation("new", modified: "2026-09-17 10:05:00", credits: 2.5, tokens: #"[{"model_id":"Claude Sonnet 4.6","warp_tokens":40000,"byok_tokens":0,"custom_endpoint_tokens":0},{"model_id":"GPT-5.3 Codex (high reasoning)","warp_tokens":1000,"byok_tokens":500,"custom_endpoint_tokens":0}]"#)
        try db.query("new2", at: "2026-09-17 11:00:00.000000")
        // Warp's earlier format, with one total per model.
        try db.conversation("new2", modified: "2026-09-17 11:01:00", credits: 1.25, tokens: #"[{"model_id":"Claude Sonnet 4.6","total_tokens":2000}]"#)

        let result = try WarpActivityReader().todaysActivity(database: db.url, since: midnight)
        #expect(result.credits == Decimal(string: "3.75"))
        #expect(result.isCreditsComplete)
        #expect(result.models.map(\.modelID) == ["Claude Sonnet 4.6", "GPT-5.3 Codex (high reasoning)"])
        #expect(result.models.map(\.totalTokens) == [42_000, 1_500])
        #expect(result.models.allSatisfy { !$0.isRequestCountKnown })
        #expect(result.latestModel == "Claude Sonnet 4.6")
    }

    /// Its totals include yesterday, so they can't be credited to today.
    @Test func leavesOutAConversationThatBeganEarlierAndSaysSo() throws {
        let db = try WarpFixtureDatabase()
        try db.query("old", at: "2026-09-16 20:00:00.000000")
        try db.query("old", at: "2026-09-17 07:00:00.000000")
        try db.conversation("old", modified: "2026-09-17 07:10:00", credits: 9, tokens: #"[{"model_id":"Claude Opus 4.6","warp_tokens":90000}]"#)
        try db.query("new", at: "2026-09-17 08:00:00.000000")
        try db.conversation("new", modified: "2026-09-17 08:01:00", credits: 1)

        let result = try WarpActivityReader().todaysActivity(database: db.url, since: midnight)
        #expect(result.credits == 1)
        #expect(!result.isCreditsComplete)
        #expect(result.models.isEmpty)
        #expect(result.requests == 2)
    }

    @Test func aQuietDayIsZeroNotUnknown() throws {
        let db = try WarpFixtureDatabase()
        try db.query("old", at: "2026-09-10 10:00:00.000000")
        try db.conversation("old", modified: "2026-09-10 10:01:00", credits: 4)

        let result = try WarpActivityReader().todaysActivity(database: db.url, since: midnight)
        #expect(result.requests == 0)
        #expect(result.credits == 0)
        #expect(result.isCreditsComplete)
    }

    @Test func aMissingDatabaseIsAnError() {
        #expect(throws: (any Error).self) {
            try WarpActivityReader().todaysActivity(database: URL(filePath: "/nonexistent/warp.sqlite"), since: midnight)
        }
    }
}

struct WarpProviderTests {
    private let noon = Date(timeIntervalSince1970: 1_789_646_400)

    private func provider(_ environment: WarpEnvironment) -> WarpProvider {
        WarpProvider(discover: { environment }, now: { [noon] in noon }, calendar: TestDates.utc)
    }

    @Test func notInstalled() async throws {
        let environment = WarpEnvironment(database: URL(filePath: "/nonexistent"), databaseExists: false, application: nil)
        #expect(try await provider(environment).fetchSnapshot(trigger: .automatic).status == .notInstalled)
    }

    @Test func showsTodaysActivityAndNoLimits() async throws {
        let db = try WarpFixtureDatabase()
        try db.query("c1", at: "2026-09-17 10:00:00.000000")
        try db.conversation("c1", modified: "2026-09-17 10:01:00", credits: 2, tokens: #"[{"model_id":"Claude Sonnet 4.6","warp_tokens":1000}]"#)
        let environment = WarpEnvironment(database: db.url, databaseExists: true, application: nil)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.activity.requestsToday == 1)
        #expect(snapshot.activity.creditsToday == 2)
        #expect(snapshot.recentModel == "Claude Sonnet 4.6")
        #expect(snapshot.modelActivity.count == 1)
    }

    /// A locked or damaged database is a failed refresh, which keeps the last reading.
    @Test func anUnreadableDatabaseIsAFailedRefresh() async throws {
        let dir = try TemporaryDirectory()
        try dir.write("warp.sqlite", text: "not a database")
        let environment = WarpEnvironment(database: dir.url.appending(path: "warp.sqlite"), databaseExists: true, application: nil)
        await #expect(throws: (any Error).self) { try await provider(environment).fetchSnapshot(trigger: .automatic) }
    }

    @Test func installedButNeverUsedShowsAQuietDay() async throws {
        let environment = WarpEnvironment(database: URL(filePath: "/nonexistent"), databaseExists: false, application: URL(filePath: "/Applications/Warp.app"))
        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.activity.requestsToday == 0)
    }
}
