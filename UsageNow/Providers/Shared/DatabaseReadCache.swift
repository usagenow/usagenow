import Foundation
import Synchronization

/// Size and modification date of one file, the cheap way to tell whether
/// it changed.
struct FileStamp: Sendable, Equatable {
    var size: UInt64
    var modified: Date

    /// `nil` when the file doesn't exist, which is itself a state to compare.
    static func of(_ url: URL, fileManager: FileManager = .default) -> FileStamp? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return FileStamp(size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0, modified: modified)
    }
}

/// Keeps the last result read from another app's SQLite database, and reads
/// again only when the database changed or the day did.
///
/// A change shows in the database file or in its write-ahead log, which
/// SQLite writes first and folds into the database later — so both are
/// compared. Reading a month of history takes a full pass over a table, and
/// most refreshes find nothing new.
final class DatabaseReadCache<Value: Sendable>: Sendable {
    private struct Key: Equatable {
        var database: FileStamp?
        var log: FileStamp?
        var period: ActivityPeriod
    }

    private let last = Mutex<(key: Key, value: Value)?>(nil)

    func value(database: URL, period: ActivityPeriod, read: () throws -> Value) rethrows -> Value {
        let key = Key(
            database: FileStamp.of(database),
            log: FileStamp.of(URL(filePath: database.path + "-wal")),
            period: period
        )
        if let cached = last.withLock({ $0 }), cached.key == key {
            return cached.value
        }
        // Read outside the lock; a failed read leaves the last result in place.
        let value = try read()
        last.withLock { $0 = (key, value) }
        return value
    }
}
