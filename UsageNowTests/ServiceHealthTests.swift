import Foundation
import Testing
@testable import UsageNow

@MainActor
struct ServiceHealthTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parsesOverallStatusWithoutAccountData() throws {
        for (indicator, expected) in [("none", ServiceHealth.Condition.operational), ("major", .incident), ("maintenance", .incident), ("new-status", .unknown)] {
            let data = Data("{\"status\":{\"indicator\":\"\(indicator)\"}}".utf8)
            let health = try ServiceHealth.parse(data, source: .openAI, at: now)
            #expect(health.condition == expected)
            #expect(health.isFresh(at: now))
            #expect(!health.isFresh(at: now.addingTimeInterval(1_201)))
            #expect(!health.isFresh(at: now.addingTimeInterval(-1)))
        }
    }

    @Test func githubActionsOutageDoesNotBecomeCopilotOutage() throws {
        let data = Data(#"{"status":{"indicator":"major"},"components":[{"name":"Actions","status":"major_outage"},{"name":"Copilot","status":"operational"}]}"#.utf8)
        #expect(try ServiceHealth.parse(data, source: .copilot, at: now).condition == .operational)
        let affected = Data(#"{"status":{"indicator":"minor"},"components":[{"name":"Copilot AI Model Providers","status":"degraded_performance"}]}"#.utf8)
        #expect(try ServiceHealth.parse(affected, source: .copilot, at: now).condition == .incident)
        #expect(try ServiceHealth.parse(Data(#"{"status":{"indicator":"none"}}"#.utf8), source: .copilot, at: now).condition == .unknown)
    }

    @Test func optInOnlyEnabledProvidersAndTenMinuteCache() async {
        let transport = StatusStub()
        let clock = TestClock(now)
        let store = ServiceHealthStore(transport: transport, now: { clock.now })
        await store.refreshIfNeeded()
        #expect(await transport.requests.isEmpty)
        store.configure(enabled: true, providers: [.codex, .cursor, .gemini])
        async let first: Void = store.refreshIfNeeded()
        async let second: Void = store.refreshIfNeeded()
        _ = await (first, second)
        #expect(await transport.requests.count == 2)
        #expect(Set(store.readings.keys) == [.codex, .cursor])
        await store.refreshIfNeeded()
        #expect(await transport.requests.count == 2)
        clock.advance(by: 600)
        await store.refreshIfNeeded()
        #expect(await transport.requests.count == 4)
        for request in await transport.requests {
            #expect(request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.url?.query == nil)
            #expect(ServiceStatusSource.allCases.map(\.endpoint).contains(request.url!))
        }
        store.configure(enabled: false, providers: [.codex])
        await store.refreshIfNeeded()
        #expect(store.readings.isEmpty)
        #expect(await transport.requests.count == 4)
    }

    @Test func disablingDuringRequestRejectsLateResults() async throws {
        let transport = StatusStub(delay: .milliseconds(80))
        let store = ServiceHealthStore(transport: transport)
        store.configure(enabled: true, providers: [.codex])
        let task = Task { await store.refreshIfNeeded() }
        while await transport.requests.isEmpty { await Task.yield() }
        store.configure(enabled: false, providers: [.codex])
        await task.value
        #expect(store.readings.isEmpty)
    }

    @Test func badResponsesAreUnknownNotHealthyAndAreCached() async {
        let transport = StatusStub(body: "not JSON")
        let store = ServiceHealthStore(transport: transport)
        store.configure(enabled: true, providers: [.claudeCode])
        await store.refreshIfNeeded()
        await store.refreshIfNeeded()
        #expect(store.readings[.claudeCode]?.condition == .unknown)
        #expect(await transport.requests.count == 1)
    }
}

private actor StatusStub: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    let body: String
    let delay: Duration

    init(body: String = #"{"status":{"indicator":"none"}}"#, delay: Duration = .zero) {
        self.body = body
        self.delay = delay
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if delay > .zero { try? await Task.sleep(for: delay) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
