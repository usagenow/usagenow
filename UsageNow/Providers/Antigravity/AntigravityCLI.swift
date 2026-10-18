import Foundation

/// Official read-only print command, introduced in agy 1.1.11. Never
/// substitute a prompt or read the CLI's credentials. Unknown major versions
/// must be checked before invoking print mode.
actor AntigravityCLI {
    typealias Runner = @Sendable (URL, [String]) async -> Data?
    private let run: Runner
    private let cache: QuotaCache<[UsageWindow]>
    private(set) var available = false

    init(run: @escaping Runner = AntigravityCLIProcess.output,
         lastKnownLimits: QuotaCacheStore<[UsageWindow]>? = nil) {
        self.run = run
        cache = QuotaCache(minimumInterval: 5 * 60, retention: 24 * 60 * 60, store: lastKnownLimits)
    }

    func windows(executable: URL, trigger: RefreshTrigger, now: @escaping @Sendable () -> Date) async -> QuotaCache<[UsageWindow]>.Entry? {
        await cache.value(trigger: trigger, now: now) { [self] in
            await fetch(executable: executable)
        }
    }

    private func fetch(executable: URL) async -> QuotaFetchResult<[UsageWindow]> {
        available = false
        guard let version = await run(executable, ["--version"]),
              Self.supportsReport(String(decoding: version, as: UTF8.self)),
              let data = await run(executable, ["-p", "/usage", "--output-format", "json"]),
              let windows = Self.parse(data) else { return .unavailable }
        available = true
        return .value(windows)
    }

    static func supportsReport(_ version: String) -> Bool {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        // Version 1.2.2 prints just the semantic version. Do not guess from
        // arbitrary banners, prereleases or a newer incompatible major.
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]), major == 1 else { return false }
        return minor > 1 || (minor == 1 && patch >= 11)
    }

    /// Only consume the CLI's own command envelope, never an agent answer,
    /// free-form text, token counters or a model-generated JSON object.
    static func parse(_ data: Data) -> [UsageWindow]? {
        struct Report: Decodable {
            struct Command: Decodable {
                struct Payload: Decodable {
                    struct Group: Decodable {
                        struct Bucket: Decodable {
                            let id: String
                            let window: String?
                            let remaining_fraction: Double?
                            let reset_time: String?
                            let disabled: Bool?
                        }
                        let name: String
                        let buckets: [Bucket]
                    }
                    let groups: [Group]
                }
                let name: String
                let data: Payload
            }
            let status: String
            let conversation_id: String
            let num_turns: Int
            let command: Command
        }
        guard data.count <= 512 * 1_024,
              let report = try? JSONDecoder().decode(Report.self, from: data),
              report.status == "SUCCESS", report.num_turns == 0,
              report.conversation_id.isEmpty, report.command.name == "usage" else { return nil }
        var windows: [UsageWindow] = []
        for group in report.command.data.groups {
            for bucket in group.buckets where bucket.disabled != true {
                guard let fraction = bucket.remaining_fraction, fraction.isFinite,
                      (0...1).contains(fraction),
                      let kind = AntigravityQuotaParser.kind(for: bucket.window ?? bucket.id) else { continue }
                let window = UsageWindow(kind: kind, scope: AntigravityQuotaParser.scopeName(group.name),
                    usage: UsagePercentage(percent: (1 - fraction) * 100),
                    resetsAt: bucket.reset_time.flatMap(SessionTimestamp.parse))
                // Duplicate scopes/windows are ambiguous, not extra accounts.
                guard !windows.contains(where: { $0.id == window.id }) else { return nil }
                windows.append(window)
            }
        }
        guard !windows.isEmpty || report.command.data.groups.isEmpty else { return nil }
        return windows.sortedForDisplay()
    }
}

/// Bounded stdout in memory, discarded stderr, no stdin and no project
/// directory. Execution stays off Swift's cooperative thread pool.
enum AntigravityCLIProcess {
    static func output(executable: URL, arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(executable: executable, arguments: arguments))
            }
        }
    }

    private static func run(executable: URL, arguments: [String]) -> Data? {
        // Defense in depth: this runner has no arbitrary prompt facility.
        guard arguments == ["--version"] || arguments == ["-p", "/usage", "--output-format", "json"] else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = URL(filePath: "/", directoryHint: .isDirectory)
        process.environment = ["HOME": NSHomeDirectory(), "USER": NSUserName(), "LOGNAME": NSUserName(),
                               "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "NO_COLOR": "1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let running = TerminableProcess(process)
        let watchdog = DispatchWorkItem { running.terminate() }
        let hardStop = DispatchWorkItem { running.forceTerminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
        DispatchQueue.global().asyncAfter(deadline: .now() + 21, execute: hardStop)
        defer { watchdog.cancel(); hardStop.cancel(); try? pipe.fileHandleForReading.close() }
        var data = Data()
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 8_192), !chunk.isEmpty {
                guard data.count + chunk.count <= 512 * 1_024 else { running.forceTerminate(); process.waitUntilExit(); return nil }
                data.append(chunk)
            }
        } catch { running.forceTerminate(); process.waitUntilExit(); return nil }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
