import Foundation

/// Where telemetry goes, if anywhere.
struct TelemetryConfiguration: Sendable, Equatable {
    /// `nil` turns network telemetry off entirely: the client then behaves
    /// exactly like `NoOpTelemetryClient`.
    var endpoint: URL?

    static let disabled = TelemetryConfiguration(endpoint: nil)

    /// No production endpoint exists yet, so release builds send nothing.
    /// Debug builds can target a local server for development:
    /// `-UsageNowTelemetryEndpoint http://localhost:8787/v1/events`
    static func current(defaults: UserDefaults = .standard) -> TelemetryConfiguration {
        #if DEBUG
        if let value = defaults.string(forKey: "UsageNowTelemetryEndpoint"),
           let url = URL(string: value),
           url.scheme == "http" || url.scheme == "https" {
            return TelemetryConfiguration(endpoint: url)
        }
        #endif
        return .disabled
    }
}

/// Posts telemetry events as JSON with `URLSession`.
///
/// Sends nothing unless an endpoint is configured *and* the user opted in;
/// the installation identity is only created when a request is actually
/// made. Failures are dropped silently: no retries, no queue, no errors
/// shown, and nothing waits on it.
actor NetworkTelemetryClient: TelemetryClient {
    static let timeout: TimeInterval = 5

    private let configuration: TelemetryConfiguration
    private let identity: InstallationIdentity
    private let transport: any HTTPTransport
    private let isSharingEnabled: @Sendable () async -> Bool
    private let environment: TelemetryEnvironment
    private let now: @Sendable () -> Date

    init(
        configuration: TelemetryConfiguration,
        identity: InstallationIdentity,
        transport: any HTTPTransport = URLSessionTransport.ephemeral(timeout: NetworkTelemetryClient.timeout),
        isSharingEnabled: @escaping @Sendable () async -> Bool,
        environment: TelemetryEnvironment = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configuration = configuration
        self.identity = identity
        self.transport = transport
        self.isSharingEnabled = isSharingEnabled
        self.environment = environment
        self.now = now
    }

    func send(_ event: TelemetryEvent) async {
        guard let endpoint = configuration.endpoint, await isSharingEnabled() else { return }
        guard let installationID = try? identity.identifier() else {
            Log.telemetry.debug("No installation identity; event dropped")
            return
        }

        let payload = TelemetryPayload(event: event, installationID: installationID, environment: environment, date: now())
        var request = URLRequest(url: endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            let (_, response) = try await transport.send(request)
            Log.telemetry.debug("Sent \(event.rawValue, privacy: .public): HTTP \(response.statusCode, privacy: .public)")
        } catch {
            Log.telemetry.debug("Dropped \(event.rawValue, privacy: .public): request failed")
        }
    }
}
