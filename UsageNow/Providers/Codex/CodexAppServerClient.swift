import Foundation

/// Reads account state and rate limits from the official Codex app-server
/// (`codex app-server`: JSON-RPC 2.0 over stdio, one JSON object per line).
///
/// The app-server is part of the installed Codex CLI and authenticates with
/// Codex's own credentials; UsageNow never reads or copies them, and never
/// calls Codex backend endpoints itself. The protocol is marked
/// experimental by Codex, so every failure here is non-fatal.
struct CodexAppServerClient: Sendable {
    enum Outcome: Sendable, Equatable {
        case rateLimits(CodexRateLimitSnapshot)
        /// Signed in with ChatGPT, but the app-server returned no rate limits —
        /// for example an error for this plan. The plan is still known, and
        /// limits recorded in session files remain usable.
        case signedInWithoutRateLimits(planType: String?)
        case notSignedIn
        /// Signed in with an API key or another provider: no subscription limits apply.
        case noSubscriptionLimits

        /// The plan the account reports, when rate limits didn't carry one.
        var accountPlanType: String? {
            switch self {
            case .rateLimits(let snapshot): snapshot.planType
            case .signedInWithoutRateLimits(let planType): planType
            case .notSignedIn, .noSubscriptionLimits: nil
            }
        }
    }

    enum ClientError: Error, Equatable {
        case launchFailed
        case timedOut
        case unexpectedResponse
        case rpcError(code: Int)
    }

    let executable: URL
    var codexHome: URL?
    var timeout: Duration = .seconds(10)

    func fetch(now: @escaping @Sendable () -> Date = { .now }) async throws -> Outcome {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ClientError.launchFailed
        }

        let running = RunningProcess(process: process, input: input.fileHandleForWriting)
        defer { running.stop() }
        let watchdog = Task { [timeout] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { running.stop() }
        }
        defer { watchdog.cancel() }

        var session = JSONRPCSession(input: input.fileHandleForWriting, output: output.fileHandleForReading)
        do {
            _ = try await session.request(1, method: "initialize", params: [
                "clientInfo": ["name": "usagenow", "title": "UsageNow", "version": AppInfo.version],
            ])
            try session.notify("initialized")

            let account = try await session.request(2, method: "account/read", params: ["refreshToken": false])
            let accountResult = try JSONDecoder().decode(AccountResult.self, from: account)
            switch accountResult.account?.type {
            case "chatgpt":
                break
            case nil:
                return accountResult.requiresOpenaiAuth ? .notSignedIn : .noSubscriptionLimits
            default:
                return .noSubscriptionLimits
            }

            let planType = accountResult.account?.planType
            let limits: Data
            do {
                limits = try await session.request(3, method: "account/rateLimits/read", params: nil)
            } catch ClientError.rpcError {
                return .signedInWithoutRateLimits(planType: planType)
            }
            guard let result = try? JSONDecoder().decode(CodexAppServerRateLimitsResult.self, from: limits) else {
                return .signedInWithoutRateLimits(planType: planType)
            }
            var snapshot = result.snapshot(capturedAt: now())
            snapshot.planType = snapshot.planType ?? planType
            return .rateLimits(snapshot)
        } catch let error as ClientError {
            throw error
        } catch is DecodingError {
            throw ClientError.unexpectedResponse
        } catch {
            // The pipe closed, usually because the watchdog stopped the process.
            throw ClientError.timedOut
        }
    }

    private struct AccountResult: Decodable {
        struct Account: Decodable {
            var type: String?
            /// Present for ChatGPT accounts, e.g. "team".
            var planType: String?
        }

        var account: Account?
        var requiresOpenaiAuth: Bool
    }
}

/// Minimal JSON-RPC client over the app-server's stdio pipes.
private struct JSONRPCSession {
    let input: FileHandle
    var lines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.lines = output.bytes.lines.makeAsyncIterator()
    }

    /// Sends a request and returns the raw JSON of its `result`.
    mutating func request(_ id: Int, method: String, params: [String: Any]?) async throws -> Data {
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)

        while let line = try await lines.next() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["method"] == nil,
                  (object["id"] as? Int) == id else {
                continue // Notifications and unrelated messages.
            }
            if let error = object["error"] as? [String: Any] {
                throw CodexAppServerClient.ClientError.rpcError(code: error["code"] as? Int ?? 0)
            }
            guard let result = object["result"] else {
                throw CodexAppServerClient.ClientError.unexpectedResponse
            }
            return try JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed)
        }
        throw CodexAppServerClient.ClientError.timedOut
    }

    func notify(_ method: String) throws {
        try send(["method": method])
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }
}

/// Stops the app-server once, from whichever path gets there first.
private final class RunningProcess: @unchecked Sendable {
    private let process: Process
    private let input: FileHandle
    private let lock = NSLock()
    private var stopped = false

    init(process: Process, input: FileHandle) {
        self.process = process
        self.input = input
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        // Closing stdin asks the app-server to exit; terminate in case it doesn't.
        try? input.close()
        if process.isRunning { process.terminate() }
    }
}
