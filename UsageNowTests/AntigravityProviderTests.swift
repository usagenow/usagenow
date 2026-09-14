import Foundation
import Synchronization
import Testing
@testable import UsageNow

/// Antigravity limits come from Antigravity CLI's own loopback server. The
/// response shape follows open implementations of the same RPC.
struct AntigravityProviderTests {
    private let noon = TestDates.noon

    private func environment(installed: Bool = true) -> AntigravityEnvironment {
        AntigravityEnvironment(home: URL(filePath: "/nonexistent/.gemini/antigravity-cli"), homeExists: installed, executable: nil)
    }

    private func server(ports: [Int], transport: any HTTPTransport, store: QuotaCacheStore<[UsageWindow]>? = nil) -> AntigravityLocalServer {
        let endpoints = ports.map { AntigravityEndpoint(port: $0, csrf: "test-csrf") }
        return AntigravityLocalServer(discover: { endpoints }, transport: transport, minimumInterval: 0, lastKnownLimits: store)
    }

    private func provider(_ server: AntigravityLocalServer, installed: Bool = true, at date: Date? = nil) -> AntigravityProvider {
        let now = date ?? noon
        return AntigravityProvider(discover: { environment(installed: installed) }, server: server, now: { now })
    }

    // MARK: States

    @Test func notInstalled() async throws {
        let snapshot = try await provider(server(ports: [], transport: RoutedTransport()), installed: false).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notInstalled)
    }

    @Test func agyNotRunningSaysSo() async throws {
        let snapshot = try await provider(server(ports: [], transport: RoutedTransport())).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.quotaUnavailableReason == .toolNotRunning)
        #expect(QuotaUnavailableReason.toolNotRunning.message(for: .antigravity) == "Open the Antigravity app to update usage limits.")
    }

    @Test func runningAgyGivesScopedWindowsAndTier() async throws {
        let transport = RoutedTransport()
        let snapshot = try await provider(server(ports: [52431], transport: transport)).fetchSnapshot(trigger: .automatic)

        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .fiveHour, .weekly, .weekly])
        #expect(snapshot.window(.weekly)?.scope != nil)
        #expect(snapshot.windows.first { $0.kind == .weekly && $0.scope == "Claude and GPT" }?.usage?.remainingDisplayValue == 10)
        #expect(snapshot.mostCriticalWindow?.scope == "Claude and GPT")
        #expect(snapshot.planName == "Starter")
        #expect(snapshot.quotaUnavailableReason == nil)
        #expect(snapshot.modelActivity.isEmpty, "No activity is guessed from agy's binary conversation files")

        let requests = await transport.requests
        let summary = try #require(requests.first)
        #expect(summary.url?.absoluteString == "https://127.0.0.1:52431/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
        #expect(summary.httpMethod == "POST")
        #expect(summary.value(forHTTPHeaderField: "Authorization") == nil, "No credentials are sent")
        #expect(summary.value(forHTTPHeaderField: "x-codeium-csrf-token") == "test-csrf")
        #expect(summary.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(summary.httpBody == Data("{}".utf8))
    }

    @Test func fallsBackToPlainHTTPAndOtherPorts() async throws {
        let transport = RoutedTransport(failing: ["https://127.0.0.1:1111", "http://127.0.0.1:1111", "https://127.0.0.1:2222"])
        let snapshot = try await provider(server(ports: [1111, 2222], transport: transport)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.count == 4)
        #expect(await transport.requests.contains { $0.url?.absoluteString.hasPrefix("http://127.0.0.1:2222/") == true })
    }

    @Test func limitsStayStaleAfterAgyQuitsAndAcrossARelaunch() async throws {
        let memory = MemoryQuotaStore()
        _ = try await provider(server(ports: [52431], transport: RoutedTransport(), store: memory.store)).fetchSnapshot(trigger: .automatic)

        let later = provider(server(ports: [], transport: RoutedTransport(), store: memory.store), at: noon.addingTimeInterval(600))
        let snapshot = try await later.fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.count == 4)
        #expect(snapshot.limitsUpdatedAt == noon)
        #expect(snapshot.quotaUnavailableReason == .toolNotRunning, "The way to update stays visible under stale limits")
    }

    @Test func anUnusableAnswerIsNotMistakenForAgyNotRunning() async throws {
        let transport = RoutedTransport(summaryBody: #"{"unexpected":true}"#)
        let snapshot = try await provider(server(ports: [52431], transport: transport)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.quotaUnavailableReason == .temporarilyUnavailable)
    }

    // MARK: Discovery and transport

    @Test func lsofOutputYieldsOnlyLoopbackPorts() {
        let output = "p4242\nn127.0.0.1:52431\nn[::1]:52432\nn*:8080\nn192.168.1.10:9000\nn127.0.0.1:52431\nsomething else\n"
        #expect(AntigravityProcessScan.ports(fromLsofOutput: output) == [52431, 52432])
        #expect(AntigravityProcessScan.ports(fromLsofOutput: "") == [])
    }

    @Test func processScanFindsOnlyAntigravityLanguageServers() {
        let ps = """
        4242 /Applications/Antigravity.app/Contents/language_server --ide_name=antigravity --csrf_token=abc123 --extension_server_port=52431
        4243 /Applications/Windsurf.app/Contents/language_server --ide_name=windsurf --csrf_token=zzz
        4244 /usr/bin/agy
        4245 /opt/other/language_server --app_data_dir=/Users/x/.other
        """
        let found = AntigravityProcessScan.candidates(psOutput: ps)
        #expect(found.map(\.pid) == [4242])
        #expect(AntigravityProcessScan.value(of: "--csrf_token", in: found[0].command) == "abc123")
        #expect(AntigravityProcessScan.value(of: "--extension_server_port", in: found[0].command) == "52431")
    }

    @Test func pathMarkerAlsoIdentifiesAntigravity() {
        let ps = "5000 /Users/x/.antigravity-ide/bin/language_server --csrf_token=tok --extension_server_port=61000"
        #expect(AntigravityProcessScan.candidates(psOutput: ps).map(\.pid) == [5000])
    }

    @Test func loopbackTransportRefusesOtherHosts() async {
        let request = URLRequest(url: URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!)
        await #expect(throws: URLError.self) {
            _ = try await LoopbackTransport().send(request)
        }
    }

    @Test func tierNameIsShortened() {
        #expect(AntigravityUserStatus.tierName(from: Data(#"{"userStatus":{"userTier":{"name":"Antigravity Starter","id":"x"}}}"#.utf8)) == "Antigravity Starter")
        #expect(AntigravityUserStatus.displayName("Antigravity Starter") == "Starter")
        #expect(AntigravityUserStatus.displayName("Google AI Ultra") == "Google AI Ultra")
        #expect(AntigravityUserStatus.tierName(from: Data("nope".utf8)) == nil)
    }

    // MARK: Parsing

    @Test func parserAcceptsTheEnvelopeAndNestedRemaining() throws {
        let nested = #"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","remaining":{"remainingFraction":"0.5","resetTime":"2026-09-15T00:00:00Z"}}]}]}}"#
        let windows = try #require(AntigravityQuotaParser.windows(from: Data(nested.utf8)))
        #expect(windows.first?.kind == .weekly)
        #expect(windows.first?.scope == "Gemini")
        #expect(windows.first?.usage?.remainingDisplayValue == 50)
        #expect(windows.first?.resetsAt == SessionTimestamp.parse("2026-09-15T00:00:00Z"))
    }

    @Test func parserSkipsWhatItCantLabel() throws {
        let json = #"{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"mystery","remainingFraction":0.2},{"bucketId":"gemini-weekly","disabled":true,"remainingFraction":0.1},{"bucketId":"gemini-weekly"},{"bucketId":"gemini-5h","remainingFraction":1.4}]}]}"#
        let windows = try #require(AntigravityQuotaParser.windows(from: Data(json.utf8)))
        #expect(windows.map(\.kind) == [.fiveHour])
        #expect(windows.first?.usage?.remainingDisplayValue == 100, "Fractions are clamped")
        #expect(AntigravityQuotaParser.windows(from: Data("[]".utf8)) == nil)
    }

    @Test(arguments: [("Gemini Models", "Gemini"), ("Claude and GPT Models", "Claude and GPT"), ("Something New", "Something New")])
    func scopeNames(displayName: String, expected: String) {
        #expect(AntigravityQuotaParser.scopeName(displayName) == expected)
    }
}

/// Answers like Antigravity CLI's loopback server, with some endpoints failing on demand.
actor RoutedTransport: HTTPTransport {
    private let failing: Set<String>
    private let summaryBody: String
    private(set) var requests: [URLRequest] = []

    init(failing: Set<String> = [], summaryBody: String = AntigravityFixture.summary) {
        self.failing = failing
        self.summaryBody = summaryBody
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!
        let origin = "\(url.scheme!)://\(url.host()!):\(url.port!)"
        if failing.contains(origin) { throw URLError(.cannotConnectToHost) }
        let body = url.lastPathComponent == "GetUserStatus" ? AntigravityFixture.userStatus : summaryBody
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

enum AntigravityFixture {
    static let summary = #"""
    {"response": {"groups": [
      {"displayName": "Gemini Models", "buckets": [
        {"bucketId": "gemini-5h", "displayName": "5-hour limit", "remainingFraction": 0.9, "resetTime": "2026-09-11T15:00:00Z"},
        {"bucketId": "gemini-weekly", "displayName": "Weekly Limit", "remainingFraction": 0.75, "resetTime": "2026-09-15T00:00:00Z"}
      ]},
      {"displayName": "Claude and GPT Models", "buckets": [
        {"bucketId": "3p-5h", "displayName": "5-hour limit", "remainingFraction": 0.6, "resetTime": "2026-09-11T15:00:00Z"},
        {"bucketId": "3p-weekly", "displayName": "Weekly Limit", "remainingFraction": 0.1, "resetTime": "2026-09-15T00:00:00Z"},
        {"bucketId": "future-bucket", "displayName": "Something new"}
      ]}
    ]}}
    """#
    static let userStatus = #"{"userStatus":{"userTier":{"id":"starter","name":"Antigravity Starter"}}}"#
}
