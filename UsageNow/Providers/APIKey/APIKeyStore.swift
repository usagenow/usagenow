import Foundation

/// The API keys a person connects providers with.
///
/// Keys are the person's own, entered by hand, one per provider. They live
/// only in this Mac's login keychain (this device only, never synced), and
/// are removed when the provider is turned off. Nothing else in UsageNow —
/// logs, the widget snapshot, telemetry, UserDefaults — ever holds one.
protocol APIKeyStoring: Sendable {
    func key(for provider: ProviderID) throws -> String?
    func setKey(_ key: String, for provider: ProviderID) throws
    func removeKey(for provider: ProviderID) throws
}

extension APIKeyStoring {
    func hasKey(for provider: ProviderID) -> Bool {
        ((try? key(for: provider)) ?? nil)?.isEmpty == false
    }
}

struct KeychainAPIKeyStore: APIKeyStoring {
    private let store: any SecureStore

    init(store: any SecureStore = KeychainStore(service: "com.usagenow.UsageNow.api-keys")) {
        self.store = store
    }

    func key(for provider: ProviderID) throws -> String? {
        try store.data(for: provider.rawValue).map { String(decoding: $0, as: UTF8.self) }
    }

    func setKey(_ key: String, for provider: ProviderID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try removeKey(for: provider)
            return
        }
        try store.setData(Data(trimmed.utf8), for: provider.rawValue)
    }

    func removeKey(for provider: ProviderID) throws {
        try store.removeData(for: provider.rawValue)
    }
}
