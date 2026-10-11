import Foundation

/// The API keys a person connects providers with.
///
/// Keys are the person's own, entered by hand, one per provider account
/// (`account` is an added account's id, `nil` for the first). They live
/// only in this Mac's login keychain (this device only, never synced), and
/// are removed when the provider is turned off. Nothing else in UsageNow —
/// logs, the widget snapshot, telemetry, UserDefaults — ever holds one.
protocol APIKeyStoring: Sendable {
    func key(for provider: ProviderID, account: String?) throws -> String?
    func setKey(_ key: String, for provider: ProviderID, account: String?) throws
    func removeKey(for provider: ProviderID, account: String?) throws
}

extension APIKeyStoring {
    func key(for provider: ProviderID) throws -> String? {
        try key(for: provider, account: nil)
    }

    func setKey(_ key: String, for provider: ProviderID) throws {
        try setKey(key, for: provider, account: nil)
    }

    func removeKey(for provider: ProviderID) throws {
        try removeKey(for: provider, account: nil)
    }

    func hasKey(for provider: ProviderID, account: String? = nil) -> Bool {
        ((try? key(for: provider, account: account)) ?? nil)?.isEmpty == false
    }
}

struct KeychainAPIKeyStore: APIKeyStoring {
    private let store: any SecureStore

    init(store: any SecureStore = KeychainStore(service: "com.usagenow.UsageNow.api-keys")) {
        self.store = store
    }

    func key(for provider: ProviderID, account: String?) throws -> String? {
        try store.data(for: Self.item(provider, account)).map { String(decoding: $0, as: UTF8.self) }
    }

    func setKey(_ key: String, for provider: ProviderID, account: String?) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try removeKey(for: provider, account: account)
            return
        }
        let value = try ProviderCatalog.definition(for: provider).apiKey?.normalizedCredential(trimmed) ?? trimmed
        try store.setData(Data(value.utf8), for: Self.item(provider, account))
    }

    func removeKey(for provider: ProviderID, account: String?) throws {
        try store.removeData(for: Self.item(provider, account))
    }

    /// "deepseek" for the first account, "deepseek.<id>" for an added one.
    static func item(_ provider: ProviderID, _ account: String?) -> String {
        account.map { "\(provider.rawValue).\($0)" } ?? provider.rawValue
    }
}
