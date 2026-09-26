import Foundation
import Synchronization
import Testing

@testable import UsageNow

struct DatabaseReadCacheTests {
    private let noon = TestDates.noon

    private final class Counter: Sendable {
        private let count = Mutex(0)
        var value: Int { count.withLock { $0 } }
        func next() -> Int { count.withLock { $0 += 1; return $0 } }
    }

    private func touch(_ url: URL, _ text: String, at date: Date) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test func readsAgainOnlyWhenSomethingChanged() throws {
        let dir = try TemporaryDirectory()
        let database = dir.url.appending(path: "app.db")
        let log = dir.url.appending(path: "app.db-wal")
        try touch(database, "db", at: noon)
        let cache = DatabaseReadCache<Int>()
        let reads = Counter()
        let period = ActivityPeriod(now: noon, calendar: TestDates.utc)

        #expect(cache.value(database: database, period: period) { reads.next() } == 1)
        #expect(cache.value(database: database, period: period) { reads.next() } == 1, "Nothing changed: no read")

        // SQLite writes to the log first.
        try touch(log, "wal", at: noon.addingTimeInterval(60))
        #expect(cache.value(database: database, period: period) { reads.next() } == 2)

        try touch(database, "db, checkpointed", at: noon.addingTimeInterval(120))
        #expect(cache.value(database: database, period: period) { reads.next() } == 3)

        // Midnight: "today" moved, so the same files mean different numbers.
        let tomorrow = ActivityPeriod(now: noon.addingTimeInterval(86_400), calendar: TestDates.utc)
        #expect(cache.value(database: database, period: tomorrow) { reads.next() } == 4)
        #expect(reads.value == 4)
    }

    /// A failed read is rethrown and leaves the last good result for next time.
    @Test func aFailedReadKeepsTheLastResult() throws {
        struct Locked: Error {}
        let dir = try TemporaryDirectory()
        let database = dir.url.appending(path: "app.db")
        try touch(database, "db", at: noon)
        let cache = DatabaseReadCache<Int>()
        let period = ActivityPeriod(now: noon, calendar: TestDates.utc)

        #expect(cache.value(database: database, period: period) { 7 } == 7)
        try touch(database, "changed", at: noon.addingTimeInterval(60))
        #expect(throws: Locked.self) { try cache.value(database: database, period: period) { throw Locked() } }
        try touch(database, "db", at: noon)
        #expect(cache.value(database: database, period: period) { 8 } == 7, "Back to the cached files")
    }
}
