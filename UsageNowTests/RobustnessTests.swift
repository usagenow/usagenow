import Foundation
import Testing

@testable import UsageNow

/// Regressions from the 0.6.0 code audit.
struct RobustnessTests {
    /// Lines longer than a read chunk, and lines split across chunks, come
    /// back whole — the reader's buffering is unchanged by its memory fix.
    @Test func readsLinesLongerThanAChunk() throws {
        let dir = try TemporaryDirectory()
        let long = String(repeating: "x", count: JSONLReader.chunkSize * 2 + 17)
        let url = try dir.writeJSONL("a.jsonl", lines: ["first", long, "last"], modified: .now)

        var lines: [String] = []
        let consumed = try JSONLReader.forEachLine(in: url, from: 0) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["first", long, "last"])
        #expect(consumed == UInt64(try Data(contentsOf: url).count))
    }

    /// A partial last line is left for the next read.
    @Test func leavesAPartialLineForLater() throws {
        let dir = try TemporaryDirectory()
        let url = try dir.writeJSONL("a.jsonl", lines: ["done", "still writing"], modified: .now, trailingNewline: false)
        var lines: [String] = []
        let consumed = try JSONLReader.forEachLine(in: url, from: 0) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["done"])
        #expect(consumed == 5)
    }

    /// Writing to a process that already exited used to raise SIGPIPE and
    /// end UsageNow on the spot. Now the write fails and the client says so.
    @Test func anAppServerThatQuitsEarlyIsAnErrorNotACrash() async throws {
        let client = CodexAppServerClient(executable: URL(filePath: "/usr/bin/true"), timeout: .seconds(3))
        await #expect(throws: CodexAppServerClient.ClientError.self) { try await client.fetch() }
    }

    @Test func writingToAClosedPipeThrows() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        let input = Pipe()
        process.standardInput = input
        try process.run()
        process.waitUntilExit()
        #expect(throws: (any Error).self) {
            try input.fileHandleForWriting.write(contentsOf: Data(repeating: 0x41, count: 1 << 20))
        }
    }

    /// A database that can't be opened fails once, cleanly — its handle is
    /// no longer closed a second time on the way out.
    @Test func aDatabaseThatCantBeOpenedFailsCleanly() {
        for _ in 0..<50 {
            #expect(throws: ReadOnlyDatabase.Failure.self) {
                _ = try ReadOnlyDatabase(url: URL(filePath: "/nonexistent/\(UUID()).db"))
            }
        }
    }
}
