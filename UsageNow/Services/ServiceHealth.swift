import Foundation
import Observation

/// Public service incidents are deliberately separate from account state.
enum ServiceStatusSource: String, CaseIterable, Sendable {
    case openAI, claude, cursor, copilot

    var provider: ProviderID {
        switch self {
        case .openAI: .codex
        case .claude: .claudeCode
        case .cursor: .cursor
        case .copilot: .copilot
        }
    }

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        }
    }

    var page: URL {
        switch self {
        case .openAI: URL(string: "https://status.openai.com")!
        case .claude: URL(string: "https://status.claude.com")!
        case .cursor: URL(string: "https://status.cursor.com")!
        case .copilot: URL(string: "https://www.githubstatus.com")!
        }
    }

    var endpoint: URL { page.appending(path: "api/v2/summary.json") }
}

struct ServiceHealth: Equatable, Sendable {
    enum Condition: Equatable, Sendable { case operational, incident, unknown }
    let source: ServiceStatusSource
    let condition: Condition
    let checkedAt: Date

    func isFresh(at date: Date) -> Bool {
        let age = date.timeIntervalSince(checkedAt)
        return age >= 0 && age < 20 * 60
    }

    /// Only recognize documented status values. A new shape isn't evidence
    /// that a service is healthy or that the person's sign-in has expired.
    static func parse(_ data: Data, source: ServiceStatusSource, at date: Date) throws -> ServiceHealth {
        struct Summary: Decodable {
            struct Status: Decodable { let indicator: String }
            struct Component: Decodable { let name: String; let status: String }
            let status: Status
            let components: [Component]?
        }
        let summary = try JSONDecoder().decode(Summary.self, from: data)
        let condition: Condition
        if source == .copilot {
            // A GitHub Actions or Pages outage is not a Copilot outage.
            let components = (summary.components ?? []).filter { $0.name.lowercased().contains("copilot") }
            if components.isEmpty {
                condition = .unknown
            } else if components.contains(where: { ["degraded_performance", "partial_outage", "major_outage", "under_maintenance"].contains($0.status) }) {
                condition = .incident
            } else {
                condition = components.allSatisfy { $0.status == "operational" } ? .operational : .unknown
            }
        } else {
            // Explicitly labelled as the service's overall status, not a
            // diagnosis of the account or a particular model/endpoint.
            condition = switch summary.status.indicator {
            case "none": .operational
            case "minor", "major", "critical", "maintenance": .incident
            default: .unknown
            }
        }
        return ServiceHealth(source: source, condition: condition, checkedAt: date)
    }
}

/// No account input, credentials, cookies, persistent cache or redirects.
struct ServiceStatusTransport: HTTPTransport {
    enum Failure: Error { case invalidResponse, tooLarge }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == request.url else { throw Failure.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 512 * 1_024 else { throw Failure.tooLarge }
            data.append(byte)
        }
        return (data, http)
    }
}

@Observable
@MainActor
final class ServiceHealthStore {
    private(set) var readings: [ProviderID: ServiceHealth] = [:]
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var providers: Set<ProviderID> = []
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var lastAttempt: Date?

    init(transport: any HTTPTransport = ServiceStatusTransport(), now: @escaping @Sendable () -> Date = { .now }) {
        self.transport = transport
        self.now = now
    }

    func configure(enabled: Bool, providers: Set<ProviderID>) {
        guard self.enabled != enabled || self.providers != providers else { return }
        revision += 1
        inFlight?.cancel()
        inFlight = nil
        lastAttempt = nil
        self.enabled = enabled
        self.providers = providers
        readings = enabled ? readings.filter { providers.contains($0.key) } : [:]
    }

    func refreshIfNeeded() async {
        guard enabled else { return }
        if let inFlight { await inFlight.value; return }
        let date = now()
        guard lastAttempt.map({ date.timeIntervalSince($0) >= 10 * 60 }) ?? true else { return }
        let sources = ServiceStatusSource.allCases.filter { providers.contains($0.provider) }
        guard !sources.isEmpty else { return }
        lastAttempt = date
        let revision = revision
        let transport = transport
        let task = Task { [weak self] in
            await withTaskGroup(of: ServiceHealth.self) { group in
                for source in sources {
                    group.addTask {
                        do {
                            var request = URLRequest(url: source.endpoint)
                            request.setValue("application/json", forHTTPHeaderField: "Accept")
                            let (data, response) = try await transport.send(request)
                            guard response.statusCode == 200, data.count <= 512 * 1_024 else { throw ServiceStatusTransport.Failure.invalidResponse }
                            return try ServiceHealth.parse(data, source: source, at: date)
                        } catch {
                            return ServiceHealth(source: source, condition: .unknown, checkedAt: date)
                        }
                    }
                }
                for await reading in group {
                    guard !Task.isCancelled, let self, self.revision == revision else { continue }
                    self.readings[reading.source.provider] = reading
                }
            }
            if let self, self.revision == revision { self.inFlight = nil }
        }
        inFlight = task
        await task.value
    }
}
