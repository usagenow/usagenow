import Foundation

struct ProviderConnectionVerifier: Sendable {
    var transport: any HTTPTransport = APIKeyTransport.shared

    func verify(_ credential: String, for id: ProviderID) async throws -> String {
        guard let provider = APIKeyProvider.connected(id, keys: NoStoredCredentials(), transport: transport) else {
            throw APIKeyClient.Failure.invalidCredential
        }
        return try await provider.verifyCredential(credential)
    }
}

/// A verifier cannot accidentally touch existing credentials.
private struct NoStoredCredentials: APIKeyStoring {
    func key(for provider: ProviderID, account: String?) throws -> String? { nil }
    func setKey(_ key: String, for provider: ProviderID, account: String?) throws { throw APIKeyClient.Failure.invalidCredential }
    func removeKey(for provider: ProviderID, account: String?) throws { throw APIKeyClient.Failure.invalidCredential }
}
