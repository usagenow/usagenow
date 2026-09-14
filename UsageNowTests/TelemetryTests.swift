import Foundation
import Synchronization
import Testing
@testable import UsageNow

struct InstallationIdentityTests {
    @Test func persistsAcrossInstances() throws {
        let store = InMemorySecureStore()
        let first = try InstallationIdentity(store: store).identifier()
        let second = try InstallationIdentity(store: store).identifier()
        #expect(first == second)
    }

    @Test func isOnlyCreatedOnDemand() throws {
        let store = InMemorySecureStore()
        let identity = InstallationIdentity(store: store)
        #expect(identity.existingIdentifier() == nil)
        #expect(store.isEmpty)
        _ = try identity.identifier()
        #expect(identity.existingIdentifier() != nil)
    }

    @Test func resetCreatesANewIdentity() throws {
        let store = InMemorySecureStore()
        let identity = InstallationIdentity(store: store)
        let original = try identity.identifier()
        try identity.reset()
        #expect(identity.existingIdentifier() == nil)
        #expect(try identity.identifier() != original)
    }
}

struct NetworkTelemetryClientTests {
    private let endpoint = URL(string: "https://telemetry.example.invalid/v1/events")!
    private let environment = TelemetryEnvironment(appVersion: "0.2.0", build: "7", macOSVersion: "15.4.1", architecture: "arm64")

    private func client(
        endpoint: URL?,
        enabled: Bool,
        transport: StubTransport,
        store: InMemorySecureStore = InMemorySecureStore()
    ) -> NetworkTelemetryClient {
        NetworkTelemetryClient(
            configuration: TelemetryConfiguration(endpoint: endpoint),
            identity: InstallationIdentity(store: store),
            transport: transport,
            isSharingEnabled: { enabled },
            environment: environment,
            now: { TestDates.noon }
        )
    }

    @Test func sendsNothingWhenSharingIsOff() async {
        let transport = StubTransport(status: 204, body: "")
        let store = InMemorySecureStore()
        let telemetry = client(endpoint: endpoint, enabled: false, transport: transport, store: store)
        for event in TelemetryEvent.allCases { await telemetry.send(event) }
        #expect(await transport.requests.isEmpty)
        #expect(store.isEmpty, "No identity should be generated for disabled telemetry")
    }

    @Test func sendsNothingWithoutEndpoint() async {
        let transport = StubTransport(status: 204, body: "")
        let store = InMemorySecureStore()
        let telemetry = client(endpoint: nil, enabled: true, transport: transport, store: store)
        await telemetry.send(.appActive)
        #expect(await transport.requests.isEmpty)
        #expect(store.isEmpty)
    }

    @Test func payloadContainsOnlyAllowedFields() async throws {
        let transport = StubTransport(status: 204, body: "")
        let telemetry = client(endpoint: endpoint, enabled: true, transport: transport)
        await telemetry.send(.codexDetected)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == endpoint)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(Set(json.keys) == ["event", "installation_id", "app_version", "build", "macos_version", "architecture", "timestamp"])
        #expect(json["event"] == "codex_detected")
        #expect(json["app_version"] == "0.2.0")
        #expect(json["macos_version"] == "15.4.1")
        #expect(json["timestamp"] == "2026-09-11T12:00:00Z")
        #expect(UUID(uuidString: json["installation_id"] ?? "") != nil)
    }

    /// The payload is the only thing that leaves the Mac, so its shape is
    /// pinned: no future change may add a field without failing this test.
    @Test func everyEventSendsTheSameSafeFields() async throws {
        for event in TelemetryEvent.allCases {
            let transport = StubTransport(status: 204, body: "")
            await client(endpoint: endpoint, enabled: true, transport: transport).send(event)
            let body = try #require(await transport.requests.first?.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(Set(json.keys) == ["event", "installation_id", "app_version", "build", "macos_version", "architecture", "timestamp"])
            #expect(json["event"] == event.rawValue)
        }
    }

    @Test func eventNamesAreStable() {
        #expect(Set(TelemetryEvent.allCases.map(\.rawValue)) == [
            "first_launch", "app_active", "app_updated", "codex_detected", "claude_detected", "gemini_detected", "antigravity_detected",
        ])
    }

    @Test(arguments: [
        "https://telemetry.example.invalid/v1/events",
        "",
        "not a url",
        "ftp://telemetry.example.invalid/v1/events",
        "/v1/events",
    ])
    func onlyAbsoluteWebEndpointsAreAccepted(value: String) {
        let url = TelemetryConfiguration.endpoint(from: value)
        #expect((url != nil) == value.hasPrefix("https://"))
    }

    @Test func noEndpointIsConfiguredByDefault() {
        // A release built from this repository sends nothing until an
        // endpoint is set through USAGENOW_TELEMETRY_ENDPOINT.
        #expect(TelemetryConfiguration.endpoint(from: nil) == nil)
    }

    @Test func failuresAreSilent() async {
        let transport = StubTransport(status: 500, body: "")
        await client(endpoint: endpoint, enabled: true, transport: transport).send(.firstLaunch)
        #expect(await transport.requests.count == 1)
    }
}

@MainActor
struct TelemetryReporterTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "TelemetryReporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func reporter(
        client: RecordingTelemetryClient,
        defaults: UserDefaults,
        sharing: Bool,
        version: String = "0.2.0",
        now: Date = TestDates.noon,
        store: InMemorySecureStore = InMemorySecureStore()
    ) -> (TelemetryReporter, AnalyticsPreferences) {
        let preferences = AnalyticsPreferences(defaults: defaults)
        preferences.isSharingEnabled = sharing
        let reporter = TelemetryReporter(
            client: client,
            preferences: preferences,
            identity: InstallationIdentity(store: store),
            defaults: defaults,
            environment: TelemetryEnvironment(appVersion: version, build: "1", macOSVersion: "15.0.0", architecture: "arm64"),
            now: { now },
            calendar: TestDates.utc
        )
        return (reporter, preferences)
    }

    @Test func reportsNothingWhileSharingIsOff() async {
        let client = RecordingTelemetryClient()
        let (reporter, _) = reporter(client: client, defaults: makeDefaults(), sharing: false)
        await reporter.appDidBecomeActive()
        await reporter.providersDetected([.codex, .claudeCode])
        #expect(await client.events.isEmpty)
    }

    @Test func lifecycleEvents() async {
        let defaults = makeDefaults()
        let client = RecordingTelemetryClient()

        let (first, _) = reporter(client: client, defaults: defaults, sharing: true)
        await first.appDidBecomeActive()
        await first.appDidBecomeActive() // same day
        #expect(await client.events == [.firstLaunch, .appActive])

        let (updated, _) = reporter(client: client, defaults: defaults, sharing: true, version: "0.3.0", now: TestDates.noon.addingTimeInterval(86_400))
        await updated.appDidBecomeActive()
        #expect(await client.events == [.firstLaunch, .appActive, .appUpdated, .appActive])
    }

    @Test func providersAreReportedOnce() async {
        let client = RecordingTelemetryClient()
        let (reporter, _) = reporter(client: client, defaults: makeDefaults(), sharing: true)
        await reporter.providersDetected([.claudeCode])
        await reporter.providersDetected([.codex, .claudeCode])
        await reporter.providersDetected([.codex, .claudeCode])
        #expect(await client.events == [.claudeDetected, .codexDetected])
    }

    @Test func geminiIsReportedLikeTheOtherProvidersAndRoadmapEntriesAreNot() async {
        let client = RecordingTelemetryClient()
        let (reporter, _) = reporter(client: client, defaults: makeDefaults(), sharing: true)
        await reporter.providersDetected([.gemini, .deepseek, .qwen])
        await reporter.providersDetected([.gemini])
        #expect(await client.events == [.geminiDetected])
        #expect(TelemetryEvent.detected(.deepseek) == nil)
    }

    @Test func optingOutResetsIdentityAndHistory() async throws {
        let defaults = makeDefaults()
        let client = RecordingTelemetryClient()
        let store = InMemorySecureStore()
        let (reporter, preferences) = reporter(client: client, defaults: defaults, sharing: true, store: store)
        let identity = InstallationIdentity(store: store)
        _ = try identity.identifier()

        await reporter.appDidBecomeActive()
        preferences.isSharingEnabled = false
        await reporter.sharingDidChange(detectedProviders: [.codex])
        #expect(store.isEmpty)

        preferences.isSharingEnabled = true
        await reporter.sharingDidChange(detectedProviders: [.codex])
        #expect(await client.events == [.firstLaunch, .appActive, .firstLaunch, .appActive, .codexDetected])
    }
}

actor RecordingTelemetryClient: TelemetryClient {
    private(set) var events: [TelemetryEvent] = []
    func send(_ event: TelemetryEvent) async { events.append(event) }
}

final class InMemorySecureStore: SecureStore {
    private let items = Mutex<[String: Data]>([:])

    var isEmpty: Bool { items.withLock { $0.isEmpty } }

    func data(for key: String) throws -> Data? { items.withLock { $0[key] } }
    func setData(_ data: Data, for key: String) throws { items.withLock { $0[key] = data } }
    func removeData(for key: String) throws { _ = items.withLock { $0.removeValue(forKey: key) } }
}
