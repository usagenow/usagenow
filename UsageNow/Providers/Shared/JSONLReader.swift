import Foundation

/// Streams newline-delimited records from a file without loading it whole.
enum JSONLReader {
    static let chunkSize = 256 * 1024

    /// Calls `body` for each complete line starting at `offset`, and returns
    /// the offset just past the last complete line. A trailing partial line
    /// — a record the tool is still writing — is left for the next read.
    ///
    /// A line longer than `maxLineBytes` is skipped without being kept in
    /// memory: `body` never sees it. Such a line is a pasted image or a huge
    /// tool result, not a usage record, and buffering it whole would cost
    /// its size in memory on every first read.
    static func forEachLine(
        in url: URL,
        from offset: UInt64,
        maxLineBytes: Int = defaultMaxLineBytes,
        _ body: (Data) -> Void
    ) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        var buffer = Data()
        var consumed = offset
        // Bytes of an oversized line dropped so far, while its end is still
        // ahead. `nil` when the line being read is of ordinary size.
        var skipped: UInt64?
        // Each chunk is read in its own autorelease pool. Without one, every
        // chunk of the file stays alive until the whole file is read: a
        // 219 MB session file peaked at 250 MB instead of 21 MB, and a first
        // read of a month of sessions at 1.4 GB.
        while try autoreleasepool(invoking: { () throws -> Bool in
            guard var chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { return false }
            if let dropped = skipped {
                guard let end = newlineOffsets(in: chunk, from: 0).first else {
                    skipped = dropped + UInt64(chunk.count)
                    return true
                }
                // The oversized line ends here; what follows is read as usual.
                consumed += dropped + UInt64(end + 1)
                skipped = nil
                chunk = chunk.subdata(in: (chunk.startIndex + end + 1)..<chunk.endIndex)
            }
            // Only scan the new bytes for newlines; earlier ones were already checked.
            let searchFrom = buffer.count
            buffer.append(chunk)
            let base = buffer.startIndex
            var lineStart = 0
            for newline in newlineOffsets(in: buffer, from: searchFrom) {
                if newline > lineStart, newline - lineStart <= maxLineBytes {
                    body(buffer[(base + lineStart)..<(base + newline)])
                }
                consumed += UInt64(newline - lineStart + 1)
                lineStart = newline + 1
            }
            buffer.removeSubrange(base..<(base + lineStart))
            if buffer.count > maxLineBytes {
                skipped = UInt64(buffer.count)
                buffer = Data()
            }
            return true
        }) {}
        // An oversized line still being written is left for the next read,
        // like any other partial line: `consumed` stops before it.
        return consumed
    }

    /// Larger than any usage record: a reply at a model's full output limit
    /// is a few megabytes of JSON.
    static let defaultMaxLineBytes = 16 * 1024 * 1024

    /// Offsets of every newline in `data` at or after `start`, found with
    /// `memchr`: session files run to gigabytes, and a byte-by-byte search
    /// made the first read of a month of them take seconds.
    private static func newlineOffsets(in data: Data, from start: Int) -> [Int] {
        data.withUnsafeBytes { raw -> [Int] in
            guard let base = raw.baseAddress else { return [] }
            var offsets: [Int] = []
            var position = start
            while position < raw.count, let hit = memchr(base + position, 0x0A, raw.count - position) {
                let offset = base.distance(to: UnsafeRawPointer(hit))
                offsets.append(offset)
                position = offset + 1
            }
            return offsets
        }
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
    /// Whether `marker` appears anywhere in the data, via `memmem`. Used to
    /// skip lines before decoding them, so it runs on every line read.
    func contains(_ marker: Data) -> Bool {
        guard !marker.isEmpty else { return true }
        return withUnsafeBytes { haystack in
            marker.withUnsafeBytes { needle in
                guard let h = haystack.baseAddress, let n = needle.baseAddress else { return false }
                return memmem(h, haystack.count, n, needle.count) != nil
            }
        }
    }
}
