import Foundation

/// One reachable Antigravity language server: a loopback port and the CSRF
/// token that authorizes calls to it.
struct AntigravityEndpoint: Sendable, Equatable {
    var port: Int
    var csrf: String
}

/// Reads Antigravity limits from the Antigravity app's language server.
///
/// The Antigravity app runs a `language_server` on a loopback port and prints
/// that port and a CSRF token in its own command line. UsageNow reads just
/// those two arguments (via `ps`), then asks the server for the same quota
/// summary the app's `/usage` panel shows. It reads no credentials, no other
/// arguments, and no process memory, and talks only to `127.0.0.1`.
///
/// The Antigravity CLI (`agy`) runs a server too, but it keeps its CSRF token
/// in memory only, so UsageNow can't authenticate to it — the app must be
/// running. When nothing answers, the last limits stay for a day, marked stale.
actor AntigravityLocalServer {
    static let service = "exa.language_server_pb.LanguageServerService"

    enum Reachability: Sendable, Equatable {
        case unknown
        /// No Antigravity language server is answering.
        case notRunning
        case running
        /// A server answered, but its reply couldn't be used.
        case unusableAnswer
    }

    private(set) var reachability = Reachability.unknown
    private(set) var tierName: String?

    private let discover: @Sendable () async -> [AntigravityEndpoint]
    private let transport: any HTTPTransport
    private let cache: QuotaCache<[UsageWindow]>

    init(
        discover: @escaping @Sendable () async -> [AntigravityEndpoint] = { AntigravityProcessScan.endpoints() },
        transport: any HTTPTransport = LoopbackTransport(),
        minimumInterval: TimeInterval = 60,
        lastKnownLimits: QuotaCacheStore<[UsageWindow]>? = nil
    ) {
        self.discover = discover
        self.transport = transport
        self.cache = QuotaCache(minimumInterval: minimumInterval, retention: 24 * 60 * 60, store: lastKnownLimits)
    }

    func windows(trigger: RefreshTrigger, now: @escaping @Sendable () -> Date) async -> QuotaCache<[UsageWindow]>.Entry? {
        await cache.value(trigger: trigger, now: now) { [self] in
            await self.fetch()
        }
    }

    private func fetch() async -> QuotaFetchResult<[UsageWindow]> {
        let endpoints = await discover()
        guard !endpoints.isEmpty else {
            reachability = .notRunning
            return .unavailable
        }
        var answered = false
        for endpoint in endpoints {
            for scheme in ["https", "http"] {
                guard let (status, data) = await call("RetrieveUserQuotaSummary", endpoint: endpoint, scheme: scheme) else { continue }
                answered = true
                guard status == 200 else {
                    Log.provider.notice("Antigravity usage limits: language server answered HTTP \(status, privacy: .public)")
                    continue
                }
                guard let windows = AntigravityQuotaParser.windows(from: data) else {
                    Log.provider.notice("Antigravity usage limits: the summary had an unrecognized shape")
                    continue
                }
                reachability = .running
                if let (statusCode, body) = await call("GetUserStatus", endpoint: endpoint, scheme: scheme), statusCode == 200 {
                    tierName = AntigravityUserStatus.tierName(from: body)
                }
                return .value(windows)
            }
        }
        reachability = answered ? .unusableAnswer : .notRunning
        return .unavailable
    }

    private func call(_ method: String, endpoint: AntigravityEndpoint, scheme: String) async -> (Int, Data)? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(endpoint.port)/\(Self.service)/\(method)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        // Authorizes this call to the local server; never logged.
        request.setValue(endpoint.csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)
        guard let (data, response) = try? await transport.send(request) else { return nil }
        return (response.statusCode, data)
    }
}

/// Finds the Antigravity app's language server: its CSRF token and loopback
/// port, from its command line and listening sockets.
///
/// Reads only two of its arguments — the CSRF token and the port — and only
/// from `language_server` processes that identify themselves as Antigravity.
/// No other process's arguments are used, and no memory is read.
enum AntigravityProcessScan {
    private static let csrfFlag = "--csrf_token"
    private static let portFlag = "--extension_server_port"
    private static let markers = ["antigravity", "antigravity-ide"]

    static func endpoints() -> [AntigravityEndpoint] {
        var results: [AntigravityEndpoint] = []
        for candidate in candidates(psOutput: runPS()) {
            guard let csrf = value(of: csrfFlag, in: candidate.command), !csrf.isEmpty else { continue }
            var ports = listeningPorts(pid: candidate.pid)
            if let declared = value(of: portFlag, in: candidate.command).flatMap({ Int($0) }), !ports.contains(declared) {
                ports.insert(declared, at: 0)
            }
            for port in ports where !results.contains(where: { $0.port == port }) {
                results.append(AntigravityEndpoint(port: port, csrf: csrf))
            }
        }
        return results
    }

    /// `language_server` processes that identify as Antigravity, PID and command.
    static func candidates(psOutput: String) -> [(pid: Int32, command: String)] {
        var found: [(pid: Int32, command: String)] = []
        for rawLine in psOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }),
                  let pid = Int32(line[..<space]) else { continue }
            let command = String(line[line.index(after: space)...])
            let lower = command.lowercased()
            guard lower.contains("language_server") else { continue }
            let ideName = value(of: "--ide_name", in: command)?.lowercased()
                ?? value(of: "--override_ide_name", in: command)?.lowercased()
                ?? value(of: "--app_data_dir", in: command)?.lowercased()
            // Prefer the explicit ide name; otherwise fall back to the install path.
            let matches = ideName.map { name in markers.contains { name == $0 } }
                ?? lower.contains("antigravity")
            if matches { found.append((pid, command)) }
        }
        return found
    }

    /// The value of `flag` (as `flag value` or `flag=value`) in a command line.
    static func value(of flag: String, in command: String) -> String? {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let prefix = flag + "="
        for (index, part) in parts.enumerated() {
            if part == flag, index + 1 < parts.count { return parts[index + 1] }
            if part.hasPrefix(prefix) { return String(part.dropFirst(prefix.count)) }
        }
        return nil
    }

    /// Loopback TCP ports a process listens on, from `lsof -Fn`.
    static func ports(fromLsofOutput output: String) -> [Int] {
        var ports: [Int] = []
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("n") {
            let name = line.dropFirst()
            guard let colon = name.lastIndex(of: ":") else { continue }
            let host = name[..<colon]
            guard host == "127.0.0.1" || host == "[::1]" || host == "localhost",
                  let port = Int(name[name.index(after: colon)...]), port > 0, !ports.contains(port) else { continue }
            ports.append(port)
        }
        return ports
    }

    private static func runPS() -> String {
        Subprocess.output(executable: "/bin/ps", arguments: ["-ax", "-o", "pid=,command="])
    }

    private static func listeningPorts(pid: Int32) -> [Int] {
        guard let lsof = ["/usr/sbin/lsof", "/usr/bin/lsof"].first(where: FileManager.default.isExecutableFile) else { return [] }
        return ports(fromLsofOutput: Subprocess.output(executable: lsof, arguments: ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"]))
    }
}

/// Runs a read-only tool and returns its stdout, with a watchdog.
enum Subprocess {
    static func output(executable: String, arguments: [String], timeout: TimeInterval = 5) -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let running = TerminableProcess(process)
        let watchdog = DispatchWorkItem { running.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}

enum AntigravityUserStatus {
    /// `userStatus.userTier.name`, when present.
    static func tierName(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let status = (object["userStatus"] as? [String: Any]) ?? ((object["response"] as? [String: Any])?["userStatus"] as? [String: Any])
        let name = ((status?["userTier"] as? [String: Any])?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    /// "Antigravity Starter" → "Starter": the card already names Antigravity.
    static func displayName(_ tierName: String) -> String {
        let prefix = "Antigravity "
        guard tierName.lowercased().hasPrefix(prefix.lowercased()), tierName.count > prefix.count else { return tierName }
        return String(tierName.dropFirst(prefix.count))
    }
}

/// HTTP to `127.0.0.1` only. The language server uses a self-signed
/// certificate, so for loopback hosts the certificate isn't validated —
/// nothing leaves the Mac. Any other host is refused.
struct LoopbackTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration, delegate: LoopbackTrust(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let host = request.url?.host(), LoopbackTrust.loopbackHosts.contains(host) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

private final class LoopbackTrust: NSObject, URLSessionDelegate, Sendable {
    static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              Self.loopbackHosts.contains(challenge.protectionSpace.host),
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
