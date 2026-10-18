import Foundation
import Testing
@testable import UsageNow

struct AntigravityCLITests {
    @Test func versionGateNeverRunsAnUnknownPrintImplementation() {
        for version in ["1.1.11", "1.1.12\n", "1.2.2"] { #expect(AntigravityCLI.supportsReport(version)) }
        for version in ["1.1.10", "1.0.99", "0.1.22", "2.0.0", "1.2.2-beta", "unknown", "agy 1.2.2"] {
            #expect(!AntigravityCLI.supportsReport(version))
        }
    }

    @Test func officialReportIsParsedWithoutGuessingPlanOrWindow() throws {
        let windows = try #require(AntigravityCLI.parse(Data(Self.report.utf8)))
        #expect(windows.count == 2)
        #expect(windows.allSatisfy { $0.kind == .weekly })
        #expect(Set(windows.compactMap(\.scope)) == ["Gemini", "Claude and GPT"])
        #expect(windows.first { $0.scope == "Gemini" }?.usage?.remainingDisplayValue == 75)
        #expect(windows.first { $0.scope == "Claude and GPT" }?.usage?.remainingDisplayValue == 40)
        #expect(windows[0].resetsAt == SessionTimestamp.parse("2026-09-15T00:00:00Z"))
        #expect(AntigravityCLI.parse(Data(Self.report.replacingOccurrences(of: "\"num_turns\":0", with: "\"num_turns\":1").utf8)) == nil)
        #expect(AntigravityCLI.parse(Data(Self.report.replacingOccurrences(of: "\"conversation_id\":\"\"", with: "\"conversation_id\":\"abc\"").utf8)) == nil)
        #expect(AntigravityCLI.parse(Data(Self.report.replacingOccurrences(of: "\"name\":\"usage\"", with: "\"name\":\"model\"").utf8)) == nil)
        #expect(AntigravityCLI.parse(Data(Self.report.replacingOccurrences(of: "SUCCESS", with: "ERROR").utf8)) == nil)
        #expect(AntigravityCLI.parse(Data(#"{"response":"Weekly 100%"}"#.utf8)) == nil)
        #expect(AntigravityCLI.parse(Data(repeating: 32, count: 512 * 1_024 + 1)) == nil)
    }

    @Test func incompatibleVersionDoesNotRunUsage() async {
        let runner = CLIFixtureRunner(version: "1.1.10")
        let client = AntigravityCLI(run: { await runner.run($0, $1) })
        let result = await client.windows(executable: URL(filePath: "/test/agy"), trigger: .manual, now: { TestDates.noon })
        #expect(result == nil)
        #expect(await runner.calls == [["--version"]])
    }

    @Test func cacheCoalescesAndKeepsLastGoodReportWithoutMarkingItFresh() async throws {
        let runner = CLIFixtureRunner()
        let client = AntigravityCLI(run: { await runner.run($0, $1) })
        let executable = URL(filePath: "/test/agy")
        async let first = client.windows(executable: executable, trigger: .automatic, now: { TestDates.noon })
        async let second = client.windows(executable: executable, trigger: .automatic, now: { TestDates.noon })
        let results = await [first, second]
        #expect(results.allSatisfy { $0?.value.count == 2 })
        #expect(await runner.calls.count == 2)
        await runner.fail()
        let later = TestDates.noon.addingTimeInterval(600)
        let cached = await client.windows(executable: executable, trigger: .manual, now: { later })
        #expect(cached?.fetchedAt == TestDates.noon)
        #expect(await client.available == false)
    }

    @Test func cliFallbackWorksWithoutIDEAndDoesNotCopyAnIDETier() async throws {
        let runner = CLIFixtureRunner()
        let environment = AntigravityEnvironment(home: URL(filePath: "/test"), homeExists: true, executable: URL(filePath: "/test/agy"))
        let provider = AntigravityProvider(discover: { environment },
            server: AntigravityLocalServer(discover: { [] }, transport: RoutedTransport()),
            cli: AntigravityCLI(run: { await runner.run($0, $1) }), now: { TestDates.noon })
        let snapshot = try await provider.fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.quotaUnavailableReason == nil)
        #expect(snapshot.planName == nil)
        #expect(snapshot.activity == .unknown)
    }

    @Test func answeringIDEKeepsPriorityAndNeverLaunchesCLI() async throws {
        let runner = CLIFixtureRunner()
        let environment = AntigravityEnvironment(home: URL(filePath: "/test"), homeExists: true, executable: URL(filePath: "/test/agy"))
        let provider = AntigravityProvider(discover: { environment },
            server: AntigravityLocalServer(discover: { [.init(port: 52431, csrf: "fixture")] }, transport: RoutedTransport()),
            cli: AntigravityCLI(run: { await runner.run($0, $1) }), now: { TestDates.noon })
        let snapshot = try await provider.fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.count == 4)
        #expect(snapshot.planName == "Starter")
        #expect(await runner.calls.isEmpty)
    }

    // Synthetic structure matching the official 1.2.2 report. No account data.
    static let report = #"""
    {"status":"SUCCESS","conversation_id":"","num_turns":0,"command":{"name":"usage","data":{"groups":[
      {"name":"Gemini Models","buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.75,"reset_time":"2026-09-15T00:00:00Z"}]},
      {"name":"Claude and GPT models","buckets":[{"id":"3p-weekly","window":"weekly","remaining_fraction":0.4,"reset_time":"2026-09-15T00:00:00Z"}]}
    ]}}}
    """#
}

private actor CLIFixtureRunner {
    let version: String
    var failing = false
    private(set) var calls: [[String]] = []
    init(version: String = "1.2.2") { self.version = version }
    func fail() { failing = true }
    func run(_ url: URL, _ arguments: [String]) async -> Data? {
        calls.append(arguments)
        await Task.yield()
        guard !failing else { return nil }
        return Data((arguments == ["--version"] ? version : AntigravityCLITests.report).utf8)
    }
}
