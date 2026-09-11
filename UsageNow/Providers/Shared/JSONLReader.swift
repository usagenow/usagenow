import Foundation

/// Streams newline-delimited records from a file without loading it whole.
enum JSONLReader {
    static let chunkSize = 256 * 1024

    /// Calls `body` for each complete line starting at `offset`, and returns
    /// the offset just past the last complete line. A trailing partial line
    /// — a record the tool is still writing — is left for the next read.
    static func forEachLine(
        in url: URL,
        from offset: UInt64,
        _ body: (Data) -> Void
    ) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        var buffer = Data()
        var consumed = offset
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            // Only scan the new bytes for newlines; earlier ones were already checked.
            var searchStart = buffer.endIndex
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while let newline = buffer[searchStart...].firstIndex(of: 0x0A) {
                let line = buffer[lineStart..<newline]
                if !line.isEmpty { body(line) }
                consumed += UInt64(newline - lineStart + 1)
                lineStart = buffer.index(after: newline)
                searchStart = lineStart
            }
            buffer.removeSubrange(buffer.startIndex..<lineStart)
        }
        return consumed
    }

    /// The complete lines within the last `maxBytes` of a file, oldest first.
    /// Used to find the most recent record without reading the whole file.
    static func trailingLines(in url: URL, maxBytes: UInt64) throws -> [Data] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > maxBytes ? size - maxBytes : 0
        try handle.seek(toOffset: start)
        guard let data = try handle.readToEnd() else { return [] }

        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        // Starting mid-file means the first line is probably cut off.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}

extension Data {
    func contains(_ marker: Data) -> Bool {
        range(of: marker) != nil
    }
}
