import Foundation
import Testing
@testable import UsageNow

struct ProviderConnectionVerifierTests {
    @Test func everyKeyConnectionReusesItsUsageReader() async throws {
        let fixtures: [(ProviderID, String, String)] = [
            (.deepseek, "test-key", #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"3"}]}"#),
            (.kimi, "test-key", #"{"status":true,"data":{"available_balance":3}}"#),
            (.openrouter, "test-key", #"{"data":{"usage":3,"limit":10}}"#),
            (.ollama, "test-key", #"{"limits":{"weekly":{"usage":0.2}}}"#),
            (.cursor, "analytics=unused; WorkosCursorSessionToken=test-cookie", #"{"individualUsage":{"plan":{"used":2,"limit":10}}}"#),
            (.copilot, "test-token", #"{"copilot_plan":"individual","quota_snapshots":{"chat":{"unlimited":true}}}"#),
            (.perplexity, "authjs.session-token=test-cookie", #"{"balance_cents":10,"total_usage_cents":0,"credit_grants":[]}"#),
            (.elevenlabs, "test-key", #"{"character_count":2,"character_limit":10}"#),
            (.zai, "test-key", #"{"success":true,"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":10}]}}"#),
            (.minimax, "subscription-test", #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_total_count":100,"current_interval_usage_count":75}]}"#),
        ]
        #expect(Set(fixtures.map { $0.0 }) == Set(ProviderCatalog.available.filter { $0.apiKey != nil }.map(\.id)))
        for (id, credential, body) in fixtures {
            let transport = StubTransport(status: 200, body: body)
            let verified = try await ProviderConnectionVerifier(transport: transport).verify(credential, for: id)
            #expect(verified == (try ProviderCatalog.definition(for: id).apiKey!.normalizedCredential(credential)))
            let requests = await transport.requests
            #expect(requests.count == 1)
            #expect(requests.first?.httpMethod == "GET")
            #expect(requests.first?.url?.host == ProviderCatalog.definition(for: id).apiKey?.host)
        }
    }

    @Test func invalidFormatAndLocalProvidersNeverSendAnything() async {
        let transport = StubTransport(status: 200, body: "{}")
        let verifier = ProviderConnectionVerifier(transport: transport)
        for (id, key) in [(ProviderID.cursor, "unnamed-cookie"), (.codex, "test"), (.claudeCode, "test"), (.elevenlabs, "bad\r\nheader")] {
            await #expect(throws: APIKeyClient.Failure.invalidCredential) { try await verifier.verify(key, for: id) }
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [401, 403]) func rejectedCredentialDoesNotVerify(_ status: Int) async {
        let verifier = ProviderConnectionVerifier(transport: StubTransport(status: status, body: "private body must not be displayed"))
        await #expect(throws: APIKeyClient.Failure.rejectedKey) { try await verifier.verify("test", for: .copilot) }
    }

    @Test func missingPermissionIsDistinctFromBadKey() async {
        let verifier = ProviderConnectionVerifier(transport: StubTransport(status: 403, body: #"{"detail":{"status":"missing_permissions"}}"#))
        await #expect(throws: APIKeyClient.Failure.permissionDenied) { try await verifier.verify("test", for: .elevenlabs) }
    }

    @Test func HTTP200WithUnrecognizedBodyIsNotAConnection() async {
        let verifier = ProviderConnectionVerifier(transport: StubTransport(status: 200, body: "{}"))
        await #expect(throws: APIKeyClient.Failure.unreadableResponse) { try await verifier.verify("test", for: .elevenlabs) }
        await #expect(throws: APIKeyClient.Failure.unreadableResponse) { try await verifier.verify("test", for: .ollama) }
    }
}

@MainActor
struct ConnectionVerificationTests {
    @Test func savesOnlyAfterVerificationAndUsesNormalizedCredential() async {
        let checker = ConnectionVerification { raw, _ in raw.trimmingCharacters(in: .whitespaces) }
        var saved = "old-connection"
        let success = await checker.checkAndSave(" test-key ", for: .elevenlabs) { saved = $0 }
        #expect(success)
        #expect(saved == "test-key")
        #expect(checker.failure == nil)
        #expect(!checker.isChecking)
    }

    @Test func failureNeverReplacesExistingKeyOrAddsAccount() async {
        let checker = ConnectionVerification { _, _ in throw APIKeyClient.Failure.rejectedKey }
        var saves = 0
        let success = await checker.checkAndSave("bad-key", for: .copilot) { _ in saves += 1 }
        #expect(!success)
        #expect(saves == 0)
        #expect(checker.failure == .rejected)
        #expect(!checker.isChecking)
    }

    @Test func duplicateClickAndCancelCannotSaveALateResponse() async {
        let gate = HeldVerification()
        let checker = ConnectionVerification { raw, _ in await gate.verify(raw) }
        var saves = 0
        let pending = Task { await checker.checkAndSave("test-key", for: .elevenlabs) { _ in saves += 1 } }
        await gate.waitUntilStarted()
        #expect(checker.isChecking)
        let duplicate = await checker.checkAndSave("test-key", for: .elevenlabs) { _ in saves += 1 }
        #expect(!duplicate)
        checker.cancel()
        await gate.release()
        #expect(await pending.value == false)
        #expect(saves == 0)
        #expect(!checker.isChecking)
        #expect(checker.failure == nil)
    }

    @Test func cancelledAttemptCannotOverwriteANewerConnection() async {
        let gate = HeldVerification()
        let checker = ConnectionVerification { raw, _ in raw == "old" ? await gate.verify(raw) : raw }
        var saved = "original"
        let pending = Task { await checker.checkAndSave("old", for: .elevenlabs) { saved = $0 } }
        await gate.waitUntilStarted()
        checker.cancel()
        #expect(await checker.checkAndSave("new", for: .elevenlabs) { saved = $0 })
        await gate.release()
        #expect(await pending.value == false)
        #expect(saved == "new")
        #expect(checker.failure == nil)
    }

    @Test func taskCancellationAlsoPreventsSave() async {
        let gate = HeldVerification()
        let checker = ConnectionVerification { raw, _ in await gate.verify(raw) }
        var saves = 0
        let pending = Task { await checker.checkAndSave("test", for: .elevenlabs) { _ in saves += 1 } }
        await gate.waitUntilStarted()
        pending.cancel()
        await gate.release()
        #expect(await pending.value == false)
        #expect(saves == 0)
        #expect(checker.failure == nil)
    }

    @Test func storageFailureIsNotReportedAsABadCredential() async {
        let checker = ConnectionVerification { raw, _ in raw }
        #expect(await checker.checkAndSave("test", for: .elevenlabs) { _ in throw TestSaveFailure() } == false)
        #expect(checker.failure == .storage)
    }

    @Test func safeFailuresDoNotExposeServerTextOrCredential() {
        #expect(ConnectionCheckFailure(APIKeyClient.Failure.invalidCredential) == .format)
        #expect(ConnectionCheckFailure(APIKeyClient.Failure.permissionDenied) == .permission)
        #expect(ConnectionCheckFailure(APIKeyClient.Failure.unreadableResponse) == .unsupported)
        #expect(ConnectionCheckFailure(URLError(.notConnectedToInternet)) == .offline)
        #expect(ConnectionCheckFailure(URLError(.timedOut)) == .unavailable)
        let error = NSError(domain: "private-token", code: 42, userInfo: [NSLocalizedDescriptionKey: "private-token"])
        #expect(!ConnectionCheckFailure(error).message.contains("private-token"))
    }
}

private struct TestSaveFailure: Error {}

private actor HeldVerification {
    private var pending: CheckedContinuation<String, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var value = ""
    func verify(_ value: String) async -> String {
        self.value = value
        return await withCheckedContinuation { pending = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { pending?.resume(returning: value); pending = nil }
}
