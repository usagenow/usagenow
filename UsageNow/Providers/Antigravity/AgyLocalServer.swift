import Foundation

/// Reads Antigravity limits from Antigravity CLI itself, while it runs.
///
/// `agy` serves its language server on a loopback port. Asked for
/// `RetrieveUserQuotaSummary`, it answers with the same limits its `/usage`
/// panel shows, fetched by `agy` with its own sign-in. UsageNow never reads
/// that sign-in, sends no credentials of any kind, and talks only to
/// `127.0.0.1`. When `agy` isn't running there's nothing to ask; the last
/// limits stay for a day, marked stale.
actor AgyLocalServer {
    /// Protocol service path of the language server.
    static let service = "exa.language_server_pb.LanguageServerService"

    enum Reachability: Sendable, Equatable {
        /// Not checked yet.
        case unknown
        /// No `agy` process is listening.
        case notRunning
        /// `agy` answered.
        case running
        /// `agy` is listening, but its answer couldn't be used.
        case unusableAnswer
    }

    private(set) var reachability = Reachability.unknown
    /// The tier `agy` reports, e.g. "Antigravity Starter".
    private(set) var tierName: String?

    private let findPorts: @Sendable () async -> [Int]
    private let transport: any HTTPTransport
    private let cache: QuotaCache<[UsageWindow]>

    init(
        findPorts: @escaping @Sendable () async -> [Int] = { await AgyProcessPorts.listening() },
        transport: any HTTPTransport = LoopbackTransport(),
        minimumInterval: TimeInterval = 60,
        lastKnownLimits: QuotaCacheStore<[UsageWindow]>? = nil
    ) {
        self.findPorts = findPorts
        self.transport = transport
        self.cache = QuotaCache(minimumInterval: minimumInterval, retention: 24 * 60 * 60, store: lastKnownLimits)
    }

    func windows(trigger: RefreshTrigger, now: @escaping @Sendable () -> Date) async -> QuotaCache<[UsageWindow]>.Entry? {
        await cache.value(trigger: trigger, now: now) { [self] in
            await self.fetch()
        }
    }

    private func fetch() async -> QuotaFetchResult<[UsageWindow]> {
        let ports = await findPorts()
        guard !ports.isEmpty else {
            reachability = .notRunning
            return .unavailable
        }
        // `agy` may listen on more than one port; the language server is the one that answers.
        var answered = false
        for port in ports {
            for scheme in ["https", "http"] {
                guard let (status, data) = await call("RetrieveUserQuotaSummary", scheme: scheme, port: port) else { continue }
                answered = true
                guard status == 200 else {
                    Log.provider.notice("Antigravity usage limits: agy answered HTTP \(status, privacy: .public)")
                    continue
                }
                guard let windows = AntigravityQuotaParser.windows(from: data) else {
                    Log.provider.notice("Antigravity usage limits: agy's summary had an unrecognized shape")
                    continue
                }
                reachability = .running
                if let (statusCode, body) = await call("GetUserStatus", scheme: scheme, port: port), statusCode == 200 {
                    tierName = AgyUserStatus.tierName(from: body)
                }
                return .value(windows)
            }
        }
        // Running but not answering usefully is a different problem from not running.
        reachability = answered ? .unusableAnswer : .notRunning
        return .unavailable
    }

    private func call(_ method: String, scheme: String, port: Int) async -> (Int, Data)? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/\(Self.service)/\(method)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        guard let (data, response) = try? await transport.send(request) else { return nil }
        return (response.statusCode, data)
    }
}

/// The ports a running `agy` listens on, from `lsof`.
///
/// Only socket metadata is read, and only loopback addresses count: the
/// command lines, environment, and memory of other processes are never read.
enum AgyProcessPorts {
    static func listening() async -> [Int] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run())
            }
        }
    }

    private static func run() -> [Int] {
        guard let lsof = ["/usr/sbin/lsof", "/usr/bin/lsof"].first(where: FileManager.default.isExecutableFile) else { return [] }
        let process = Process()
        process.executableURL = URL(filePath: lsof)
        // -c agy: processes named agy; -a: and; listening TCP; -Fn: names only.
        process.arguments = ["-nP", "-a", "-c", "agy", "-iTCP", "-sTCP:LISTEN", "-Fn"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let running = TerminableProcess(process)
        let watchdog = DispatchWorkItem { running.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return ports(fromLsofOutput: String(decoding: data, as: UTF8.self))
    }

    /// Parses `lsof -Fn` lines such as `n127.0.0.1:52431` or `n[::1]:52431`.
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
}

enum AgyUserStatus {
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
