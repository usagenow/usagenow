import Foundation
import SQLite3
import Testing

@testable import UsageNow

/// A throwaway database with OpenCode's message tables, filled with fixtures.
private final class OpenCodeFixtureDatabase {
    let url: URL
    private let directory: TemporaryDirectory
    private var handle: OpaquePointer?

    init(name: String = "opencode.db") throws {
        directory = try TemporaryDirectory()
        url = directory.url.appending(path: name)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        try execute("""
            CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT NOT NULL, session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL,
                time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            """)
    }

    deinit { sqlite3_close(handle) }

    private static func tokens(input: Int, output: Int, reasoning: Int, read: Int, write: Int) -> String {
        #"{"input":\#(input),"output":\#(output),"reasoning":\#(reasoning),"cache":{"read":\#(read),"write":\#(write)}}"#
    }

    /// An assistant message as OpenCode's `message` table stores it.
    func assistant(
        _ id: String, at date: Date, model: String = "claude-opus-5",
        input: Int = 0, output: Int = 0, reasoning: Int = 0, read: Int = 0, write: Int = 0
    ) throws {
        let millis = Int64(date.timeIntervalSince1970 * 1000)
        let data = #"{"role":"assistant","time":{"created":\#(millis)},"modelID":"\#(model)","providerID":"anthropic","mode":"build","agent":"build","path":{"cwd":"/Users/me/secret-project","root":"/"},"cost":0,"tokens":\#(Self.tokens(input: input, output: output, reasoning: reasoning, read: read, write: write))}"#
        try execute("INSERT INTO message VALUES (?, 's1', ?, ?, ?)", [.text(id), .integer(millis), .integer(millis), .text(data)])
        try execute("INSERT INTO part VALUES (?, ?, 's1', ?, ?, ?)", [.text("p-\(id)"), .text(id), .integer(millis), .integer(millis), .text(#"{"type":"text","text":"the reply, which UsageNow never reads"}"#)])
    }

    func user(_ id: String, at date: Date) throws {
        let millis = Int64(date.timeIntervalSince1970 * 1000)
        let data = #"{"role":"user","time":{"created":\#(millis)},"agent":"build","model":{"providerID":"anthropic","modelID":"claude-opus-5"}}"#
        try execute("INSERT INTO message VALUES (?, 's1', ?, ?, ?)", [.text(id), .integer(millis), .integer(millis), .text(data)])
    }

    /// An assistant message in the newer `session_message` table, which keeps
    /// the reply's text in the same JSON.
    func assistantV2(_ id: String, at date: Date, model: String = "claude-opus-5", input: Int) throws {
        let millis = Int64(date.timeIntervalSince1970 * 1000)
        let data = #"{"agent":"build","model":{"id":"\#(model)","providerID":"anthropic"},"content":[{"type":"text","id":"t1","text":"the reply"}],"tokens":\#(Self.tokens(input: input, output: 0, reasoning: 0, read: 0, write: 0)),"time":{"created":\#(millis)}}"#
        try execute("INSERT INTO session_message VALUES (?, 's1', 'assistant', ?, ?, ?, ?)", [.text(id), .integer(millis), .integer(millis), .integer(millis), .text(data)])
    }

    private func execute(_ sql: String, _ values: [ReadOnlyDatabase.Value] = []) throws {
        if values.isEmpty {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
            return
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            switch value {
            case .text(let text): sqlite3_bind_text(statement, Int32(index + 1), text, -1, transient)
            case .integer(let number): sqlite3_bind_int64(statement, Int32(index + 1), number)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
    }
}

struct OpenCodeActivityReaderTests {
    private let noon = TestDates.noon
    private var period: ActivityPeriod { ActivityPeriod(now: noon, calendar: TestDates.utc) }

    @Test func readsTodaysAnswersAndTheirHistory() throws {
        let db = try OpenCodeFixtureDatabase()
        try db.user("u1", at: noon.addingTimeInterval(-120))
        try db.assistant("a1", at: noon.addingTimeInterval(-100), input: 1_000_000)
        try db.assistant("a2", at: noon.addingTimeInterval(-86_400), input: 2_000_000)
        // Failed before the model answered.
        try db.assistant("a3", at: noon.addingTimeInterval(-50))

        let result = try OpenCodeActivityReader().activity(database: db.url, period: period)
        #expect(result.activity.tokens == 1_000_000)
        #expect(result.activity.requests == 1)
        #expect(result.activity.latestModel == "claude-opus-5")
        #expect(result.activity.estimatedCost == 5)
        #expect(result.history.days.map(\.tokens).suffix(2) == [2_000_000, 1_000_000])
        #expect(result.history.topModel == "claude-opus-5")
    }

    /// OpenCode keeps cached input and reasoning apart from `input` and
    /// `output`; each is priced as what it is.
    @Test func pricesCacheAndReasoningSeparately() throws {
        let db = try OpenCodeFixtureDatabase()
        try db.assistant("a1", at: noon, input: 0, output: 100_000, reasoning: 100_000, read: 1_000_000, write: 0)

        let result = try OpenCodeActivityReader().activity(database: db.url, period: period)
        #expect(result.activity.tokens == 1_200_000)
        // 200k output at $25/M plus 1M cache reads at $0.50/M.
        #expect(result.activity.estimatedCost == Decimal(string: "5.5"))
        #expect(result.activity.models.first?.outputTokens == 200_000)
    }

    @Test func readsTheNewerTableWhenTheOlderOneIsEmpty() throws {
        let db = try OpenCodeFixtureDatabase()
        try db.assistantV2("m1", at: noon, input: 300)

        let result = try OpenCodeActivityReader().activity(database: db.url, period: period)
        #expect(result.activity.tokens == 300)
        #expect(result.activity.requests == 1)
    }

    /// A message recorded in both tables is counted once.
    @Test func neverCountsBothTables() throws {
        let db = try OpenCodeFixtureDatabase()
        try db.assistant("a1", at: noon, input: 500)
        try db.assistantV2("m1", at: noon, input: 500)

        let result = try OpenCodeActivityReader().activity(database: db.url, period: period)
        #expect(result.activity.tokens == 500)
    }

    @Test func aDatabaseWithoutMessageTablesIsAQuietDay() throws {
        let dir = try TemporaryDirectory()
        let url = dir.url.appending(path: "opencode.db")
        var handle: OpaquePointer?
        sqlite3_open(url.path, &handle)
        sqlite3_exec(handle, "CREATE TABLE project (id TEXT)", nil, nil, nil)
        sqlite3_close(handle)

        let result = try OpenCodeActivityReader().activity(database: url, period: period)
        #expect(result.activity.tokens == 0)
        #expect(!result.history.hasActivity)
    }
}

struct OpenCodeEnvironmentTests {
    @Test func prefersTheReleaseDatabase() throws {
        let dir = try TemporaryDirectory()
        try dir.write(".local/share/opencode/opencode-dev.db", text: "")
        try dir.write(".local/share/opencode/opencode.db", text: "")
        let environment = OpenCodeEnvironment.discover(homeDirectory: dir.url)
        #expect(environment.database?.lastPathComponent == "opencode.db")
        #expect(environment.isInstalled)
    }

    @Test func fallsBackToAChannelDatabase() throws {
        let dir = try TemporaryDirectory()
        try dir.write(".local/share/opencode/opencode-beta-2.db", text: "")
        try dir.write(".local/share/opencode/auth.json", text: #"{"never":"read"}"#)
        let environment = OpenCodeEnvironment.discover(homeDirectory: dir.url)
        #expect(environment.database?.lastPathComponent == "opencode-beta-2.db")
    }

    @Test func nothingThereMeansNotInstalled() throws {
        let dir = try TemporaryDirectory()
        let environment = OpenCodeEnvironment.discover(homeDirectory: dir.url)
        #expect(environment.database == nil)
        #expect(environment.executable == nil)
    }
}

struct OpenCodeProviderTests {
    private let noon = TestDates.noon

    private func provider(_ environment: OpenCodeEnvironment) -> OpenCodeProvider {
        OpenCodeProvider(discover: { environment }, now: { [noon] in noon }, calendar: TestDates.utc)
    }

    @Test func notInstalled() async throws {
        let environment = OpenCodeEnvironment(dataDirectory: URL(filePath: "/nonexistent"), database: nil, executable: nil, application: nil)
        #expect(try await provider(environment).fetchSnapshot(trigger: .automatic).status == .notInstalled)
    }

    @Test func showsActivityAndNoLimits() async throws {
        let db = try OpenCodeFixtureDatabase()
        try db.assistant("a1", at: noon.addingTimeInterval(-60), model: "gpt-5-codex", input: 1_000)
        let environment = OpenCodeEnvironment(dataDirectory: db.url.deletingLastPathComponent(), database: db.url, executable: nil, application: nil)

        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.activity.tokensToday == 1_000)
        #expect(snapshot.activity.history?.tokens == 1_000)
        #expect(snapshot.recentModel == "gpt-5-codex")
    }

    @Test func installedButNeverUsedShowsAQuietDay() async throws {
        let environment = OpenCodeEnvironment(
            dataDirectory: URL(filePath: "/nonexistent"), database: nil, executable: URL(filePath: "/opt/homebrew/bin/opencode"), application: nil
        )
        let snapshot = try await provider(environment).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.activity.tokensToday == 0)
    }

    /// A locked or damaged database is a failed refresh, which keeps the last reading.
    @Test func anUnreadableDatabaseIsAFailedRefresh() async throws {
        let dir = try TemporaryDirectory()
        try dir.write("opencode.db", text: "not a database")
        let environment = OpenCodeEnvironment(dataDirectory: dir.url, database: dir.url.appending(path: "opencode.db"), executable: nil, application: nil)
        await #expect(throws: (any Error).self) { try await provider(environment).fetchSnapshot(trigger: .automatic) }
    }
}
