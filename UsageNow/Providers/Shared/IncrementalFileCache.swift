import Foundation

/// A session file with the attributes used to detect changes.
struct SessionFile: Sendable, Hashable {
    var url: URL
    var size: UInt64
    var modificationDate: Date
}

/// Remembers how far each file was read and the state derived from it, so
/// a refresh only parses lines appended since the previous one.
///
/// Parsing happens on this actor, never on the main actor.
actor IncrementalFileCache<State: Sendable> {
    private struct Entry {
        var offset: UInt64
        var size: UInt64
        var modificationDate: Date
        var state: State
    }

    private var entries: [URL: Entry] = [:]

    /// Folds lines appended to `file` since the last read into its state.
    ///
    /// Unchanged files aren't touched. A file that shrank was replaced or
    /// rewritten, so it's parsed again from the start.
    func state(
        for file: SessionFile,
        initial: @Sendable () -> State,
        prune: @Sendable (inout State) -> Void,
        fold: @Sendable (Data, inout State) -> Void
    ) throws -> State {
        var entry = entries[file.url]
        if let existing = entry, file.size < existing.offset {
            entry = nil
        }
        var current = entry ?? Entry(offset: 0, size: 0, modificationDate: .distantPast, state: initial())

        if current.size != file.size || current.modificationDate != file.modificationDate {
            var state = current.state
            let offset = try JSONLReader.forEachLine(in: file.url, from: current.offset) { line in
                fold(line, &state)
            }
            current = Entry(offset: offset, size: file.size, modificationDate: file.modificationDate, state: state)
        }
        prune(&current.state)
        entries[file.url] = current
        return current.state
    }

    /// Forgets files that are no longer relevant, such as yesterday's sessions.
    func retain(only files: Set<URL>) {
        entries = entries.filter { files.contains($0.key) }
    }
}

enum SessionFileFinder {
    /// `.jsonl` files under `roots` modified at or after `since`.
    ///
    /// Only reads directory metadata; file contents are left alone.
    static func jsonlFiles(in roots: [URL], modifiedSince since: Date) -> [SessionFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var files: [SessionFile] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
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
