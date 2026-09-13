import Foundation
@testable import UsageNow

/// A temporary directory removed when the value is released.
final class TemporaryDirectory: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "UsageNowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `lines` as JSONL and sets the modification date.
    @discardableResult
    func writeJSONL(_ relativePath: String, lines: [String], modified: Date, trailingNewline: Bool = true) throws -> URL {
        let file = url.appending(path: relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        return file
    }

    func append(_ lines: [String], to file: URL, modified: Date) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    }

    func write(_ relativePath: String, text: String) throws {
        let file = url.appending(path: relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
}

/// Fabricated test data. Contains no real prompts, code, credentials,
/// usernames, project names, or account identifiers.
enum TestDates {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Friday, 11 September 2026, 12:00 UTC.
    static let noon = Date(timeIntervalSince1970: 1_789_128_000)

    static func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

enum CodexFixture {
    static func usageRecord(_ date: Date, responseID: String, total: Int) -> String {
        #"{"timestamp":"\#(TestDates.iso(date))","ordinal":1,"type":"token_usage_record","payload":{"thread_id":"thread-a","response_id":"\#(responseID)","usage":{"input_tokens":\#(total - 100),"cached_input_tokens":0,"output_tokens":100,"total_tokens":\#(total)},"future_field":{"x":1}}}"#
    }

    static func tokenCount(_ date: Date, cumulative: Int, last: Int, limits: String? = nil) -> String {
        let rateLimits = limits ?? "null"
        return #"{"timestamp":"\#(TestDates.iso(date))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\#(cumulative)},"last_token_usage":{"total_tokens":\#(last)}},"rate_limits":\#(rateLimits)}}"#
    }

    static func rateLimitsOnly(_ date: Date, limits: String) -> String {
        #"{"timestamp":"\#(TestDates.iso(date))","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":\#(limits)}}"#
    }

    static func limits(primaryPercent: Double, primaryMinutes: Int, resetsAt: Date, plan: String = "plus") -> String {
        #"{"limit_id":"codex","primary":{"used_percent":\#(primaryPercent),"window_minutes":\#(primaryMinutes),"resets_at":\#(Int(resetsAt.timeIntervalSince1970))},"secondary":null,"plan_type":"\#(plan)"}"#
    }

    static func turnContext(_ date: Date, model: String) -> String {
        #"{"timestamp":"\#(TestDates.iso(date))","type":"turn_context","payload":{"cwd":"/tmp/example","model":"\#(model)","developer_instructions":"lorem ipsum"}}"#
    }

    /// Conversation content that must be ignored — even though it mentions a marker.
    static func message(_ date: Date) -> String {
        #"{"timestamp":"\#(TestDates.iso(date))","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"lorem \"token_usage_record\" ipsum"}]}}"#
    }
}

enum ClaudeFixture {
    static func assistant(
        _ date: Date,
        messageID: String,
        requestID: String,
        model: String = "claude-example-1",
        input: Int = 10,
        cacheCreation: Int = 20,
        cacheRead: Int = 30,
        output: Int = 40,
        sidechain: Bool = false
    ) -> String {
        #"{"parentUuid":"p-1","isSidechain":\#(sidechain),"type":"assistant","timestamp":"\#(TestDates.iso(date))","requestId":"\#(requestID)","message":{"id":"\#(messageID)","type":"message","role":"assistant","model":"\#(model)","content":[{"type":"text","text":"lorem ipsum"}],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreation),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"service_tier":"standard","new_field":{"a":1}}},"cwd":"/tmp/example","sessionId":"s-1"}"#
    }

    static func user(_ date: Date) -> String {
        #"{"type":"user","timestamp":"\#(TestDates.iso(date))","message":{"role":"user","content":"lorem \"usage\":{ ipsum"}}"#
    }
}

/// Gemini CLI session records, in the shape `ChatRecordingService` writes.
enum GeminiFixture {
    static func metadata(_ date: Date) -> String {
        #"{"sessionId":"s-1","projectHash":"hash","startTime":"\#(TestDates.iso(date))","lastUpdated":"\#(TestDates.iso(date))","kind":"main"}"#
    }

    /// Contains the words the parser looks for, to prove content isn't mistaken for a response.
    static func user(_ date: Date, id: String) -> String {
        #"{"id":"\#(id)","timestamp":"\#(TestDates.iso(date))","type":"user","content":[{"text":"lorem \"gemini\" \"tokens\":{ ipsum"}]}"#
    }

    static func response(
        _ date: Date,
        id: String,
        model: String? = "gemini-example-1",
        input: Int = 1_000,
        output: Int = 200,
        cached: Int = 400,
        thoughts: Int = 50,
        tool: Int = 0,
        total: Int? = 1_250,
        includeTokens: Bool = true
    ) -> String {
        let modelField = model.map { #","model":"\#($0)""# } ?? ""
        let totalField = total.map { #","total":\#($0)"# } ?? ""
        let tokens = includeTokens ? #","tokens":{"input":\#(input),"output":\#(output),"cached":\#(cached),"thoughts":\#(thoughts),"tool":\#(tool)\#(totalField)}"# : ""
        return #"{"id":"\#(id)","timestamp":"\#(TestDates.iso(date))","type":"gemini","content":[{"text":"lorem ipsum"}],"thoughts":[{"subject":"s","description":"d"}]\#(tokens)\#(modelField),"toolCalls":[]}"#
    }

    static func update(_ date: Date) -> String {
        #"{"$set":{"lastUpdated":"\#(TestDates.iso(date))"}}"#
    }

    static func rewind(to id: String) -> String {
        #"{"$rewindTo":"\#(id)"}"#
    }
}
