import Foundation
import Testing
@testable import UsageNow

struct GeminiProviderTests {
    private let noon = TestDates.noon

    private func environment(
        _ dir: TemporaryDirectory,
        authType: String? = "gemini-api-key",
        hasOAuthFile: Bool = false,
        homeExists: Bool = true,
        executable: Bool = true
    ) -> GeminiEnvironment {
        GeminiEnvironment(
            home: dir.url.appending(path: ".gemini"),
            homeExists: homeExists,
            homeIsReadable: homeExists,
            authType: authType,
            hasOAuthCredentialsFile: hasOAuthFile,
            executable: executable ? URL(filePath: "/usr/local/bin/gemini") : nil
        )
    }

    private func provider(_ environment: GeminiEnvironment, now: Date? = nil) -> GeminiProvider {
        let date = now ?? noon
        return GeminiProvider(discover: { environment }, now: { date }, calendar: TestDates.utc)
    }

    @discardableResult
    private func session(_ dir: TemporaryDirectory, _ lines: [String], project: String = "example", name: String = "session-2026-09-11T11-00-abcd1234.jsonl") throws -> URL {
        try dir.writeJSONL(".gemini/tmp/\(project)/chats/\(name)", lines: lines, modified: noon)
    }

    // MARK: Discovery and sign-in

    @Test func notInstalled() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, authType: nil, homeExists: false, executable: false)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notInstalled)
    }

    @Test func installedButNotSignedIn() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, authType: nil)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .notAuthenticated)
    }

    @Test func signedInWithoutActivityToday() async throws {
        let dir = try TemporaryDirectory()
        let snapshot = try await provider(environment(dir, authType: nil, hasOAuthFile: true)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.activity == LocalActivity(tokensToday: 0, requestsToday: 0))
        #expect(snapshot.modelActivity.isEmpty)
    }

    @Test func discoveryReadsTheAuthTypeButNotCredentials() throws {
        let dir = try TemporaryDirectory()
        try dir.write(".gemini/settings.json", text: #"{"security":{"auth":{"selectedType":"gemini-api-key"}},"ui":{"theme":"x"}}"#)
        try dir.write(".gemini/oauth_creds.json", text: #"{"access_token":"fake","refresh_token":"fake"}"#)

        let environment = GeminiEnvironment.discover(homeDirectory: dir.url)
        #expect(environment.homeExists)
        #expect(environment.authType == "gemini-api-key")
        #expect(environment.hasOAuthCredentialsFile)
        #expect(environment.isSignedIn)
        #expect(environment.sessionRoots == [dir.url.appending(path: ".gemini/tmp", directoryHint: .isDirectory)])
    }

    @Test func legacyAuthSettingIsRead() throws {
        let dir = try TemporaryDirectory()
        try dir.write("settings.json", text: #"{"selectedAuthType":"vertex-ai"}"#)
        #expect(GeminiSettings.authType(in: dir.url.appending(path: "settings.json")) == "vertex-ai")
        try dir.write("broken.json", text: "{ nope")
        #expect(GeminiSettings.authType(in: dir.url.appending(path: "broken.json")) == nil)
    }

    @Test func unreadableHomeIsUnavailable() async throws {
        let dir = try TemporaryDirectory()
        var environment = environment(dir)
        environment.homeIsReadable = false
        #expect(try await provider(environment).fetchSnapshot(trigger: .automatic).status == .unavailable)
    }

    // MARK: Activity

    @Test func structuredSessionProducesActivityAndModels() async throws {
        let dir = try TemporaryDirectory()
        try session(dir, [
            GeminiFixture.metadata(noon.addingTimeInterval(-600)),
            GeminiFixture.user(noon.addingTimeInterval(-500), id: "u1"),
            // Written first without tokens, then again once they're known.
            GeminiFixture.response(noon.addingTimeInterval(-490), id: "g1", model: "gemini-2.5-pro", includeTokens: false),
            GeminiFixture.response(noon.addingTimeInterval(-490), id: "g1", model: "gemini-2.5-pro"),
            GeminiFixture.update(noon.addingTimeInterval(-489)),
            GeminiFixture.response(noon.addingTimeInterval(-300), id: "g2", model: "gemini-2.5-flash", input: 100, output: 10, cached: 0, thoughts: 0, total: 110),
            GeminiFixture.response(noon.addingTimeInterval(-200), id: "g3", model: "gemini-2.5-pro", total: 1_250),
        ])

        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)

        #expect(snapshot.status == .available)
        #expect(snapshot.activity == LocalActivity(tokensToday: 2_610, requestsToday: 3))
        #expect(snapshot.recentModel == "gemini-2.5-pro")
        #expect(snapshot.modelActivity.map(\.displayName) == ["Gemini 2.5 Pro", "Gemini 2.5 Flash"])
        let pro = try #require(snapshot.modelActivity.first)
        #expect(pro.requests == 2)
        #expect(pro.inputTokens == 2_000)
        #expect(pro.outputTokens == 500, "Output includes reasoning tokens")
    }

    @Test func activityWithoutQuotaIsNeverGivenLimits() async throws {
        let dir = try TemporaryDirectory()
        try session(dir, [GeminiFixture.response(noon.addingTimeInterval(-60), id: "g1")])

        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.quotaUnavailableReason == nil)
        #expect(snapshot.planName == nil)
        #expect(!snapshot.capabilities.contains(.quota))
        #expect(snapshot.capabilities.contains(.tokenActivity))
        #expect(snapshot.mostCriticalWindow == nil)
    }

    @Test func activityCountsEvenWhenTheSettingIsMissing() async throws {
        let dir = try TemporaryDirectory()
        try session(dir, [GeminiFixture.response(noon.addingTimeInterval(-60), id: "g1")])
        let snapshot = try await provider(environment(dir, authType: nil)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.status == .available)
        #expect(snapshot.activity.requestsToday == 1)
    }

    @Test func unknownModelStillAppears() async throws {
        let dir = try TemporaryDirectory()
        try session(dir, [GeminiFixture.response(noon.addingTimeInterval(-60), id: "g1", model: "gemini-9-ultra-experimental")])
        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.modelActivity.first?.modelID == "gemini-9-ultra-experimental")
        #expect(snapshot.modelActivity.first?.displayName == "Gemini 9 Ultra Experimental")
    }

    @Test func malformedAndUnrelatedRecordsAreIgnored() async throws {
        let dir = try TemporaryDirectory()
        try session(dir, [
            "{ broken",
            #"{"id":"x","type":"gemini","tokens":{"input":"many"},"timestamp":"\#(TestDates.iso(noon))"}"#,
            #"{"id":"info","type":"info","content":"Signed in","tokens":{"total":5},"timestamp":"\#(TestDates.iso(noon))"}"#,
            GeminiFixture.user(noon.addingTimeInterval(-70), id: "u1"),
            GeminiFixture.rewind(to: "u1"),
            GeminiFixture.response(noon.addingTimeInterval(-60), id: "g1", model: nil),
        ])
        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 1)
        #expect(snapshot.modelActivity.isEmpty, "A response without a model counts toward totals only")
    }

    @Test func totalFallsBackToTheSumOfParts() async throws {
        let dir = try TemporaryDirectory()
        try session(dir, [GeminiFixture.response(noon.addingTimeInterval(-60), id: "g1", input: 100, output: 20, cached: 50, thoughts: 5, tool: 3, total: nil)])
        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.tokensToday == 128)
    }

    @Test func subagentSessionsCountAndOtherFilesDont() async throws {
        let dir = try TemporaryDirectory()
        try session(dir, [GeminiFixture.response(noon.addingTimeInterval(-60), id: "g1")])
        try dir.writeJSONL(".gemini/tmp/example/chats/s-1/subagent-a.jsonl", lines: [GeminiFixture.response(noon.addingTimeInterval(-50), id: "g2")], modified: noon)
        try dir.writeJSONL(".gemini/tmp/example/logs/other.jsonl", lines: [GeminiFixture.response(noon.addingTimeInterval(-40), id: "g3")], modified: noon)

        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 2)
    }

    @Test func yesterdaysResponsesAreNotCounted() async throws {
        let dir = try TemporaryDirectory()
        let midnight = TestDates.utc.startOfDay(for: noon)
        try session(dir, [
            GeminiFixture.response(midnight.addingTimeInterval(-10), id: "old"),
            GeminiFixture.response(midnight.addingTimeInterval(10), id: "new"),
        ])
        let snapshot = try await provider(environment(dir)).fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 1)
    }

    @Test func appendedResponsesArePickedUpIncrementally() async throws {
        let dir = try TemporaryDirectory()
        let file = try session(dir, [GeminiFixture.response(noon.addingTimeInterval(-120), id: "g1")])
        let gemini = provider(environment(dir))
        #expect(try await gemini.fetchSnapshot(trigger: .automatic).activity.requestsToday == 1)

        try dir.append([
            GeminiFixture.response(noon.addingTimeInterval(-60), id: "g2", includeTokens: false),
            GeminiFixture.response(noon.addingTimeInterval(-60), id: "g2", total: 2_000),
        ], to: file, modified: noon.addingTimeInterval(1))
        let snapshot = try await gemini.fetchSnapshot(trigger: .automatic)
        #expect(snapshot.activity.requestsToday == 2)
        #expect(snapshot.activity.tokensToday == 3_250)
    }
}
