import Foundation

/// Remembers what was read from files a tool rewrites whole, such as a JSON
/// array saved again after every message, so an unchanged file isn't parsed
/// again on every refresh.
///
/// Unlike `IncrementalFileCache`, there's nothing to resume from: a changed
/// file is parsed again from the start. Parsing happens on this actor.
actor WholeFileCache<Value: Sendable> {
    private struct Entry {
        var size: UInt64
        var modificationDate: Date
        var value: Value
    }

    private var entries: [URL: Entry] = [:]

    func value(for file: SessionFile, parse: @Sendable (Data) throws -> Value) throws -> Value {
        if let entry = entries[file.url], entry.size == file.size, entry.modificationDate == file.modificationDate {
            return entry.value
        }
        let value = try autoreleasepool { try parse(Data(contentsOf: file.url, options: .mappedIfSafe)) }
        entries[file.url] = Entry(size: file.size, modificationDate: file.modificationDate, value: value)
        return value
    }

    /// Forgets files that are no longer relevant.
    func retain(only files: Set<URL>) {
        entries = entries.filter { files.contains($0.key) }
    }
}

extension SessionFileFinder {
    /// Files named `name` exactly one directory below each of `roots` —
    /// `tasks/<id>/ui_messages.json` — modified at or after `since`. With
    /// `prefixedWithFolderName`, the name follows its folder's:
    /// `sessions/<id>/<id>.messages.json`.
    static func files(
        named name: String,
        oneLevelBelow roots: [URL],
        modifiedSince since: Date,
        prefixedWithFolderName: Bool = false
    ) -> [SessionFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var files: [SessionFile] = []
        for root in roots {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for folder in folders {
                let url = folder.appending(path: prefixedWithFolderName ? folder.lastPathComponent + name : name)
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= since else { continue }
                files.append(SessionFile(url: url, size: UInt64(values.fileSize ?? 0), modificationDate: modified))
            }
        }
        return files
    }
}
