import Foundation

/// What a provider's official balance or usage endpoint says.
struct APIKeyReading: Sendable, Equatable {
    var balance: AccountBalance?
    var windows: [UsageWindow] = []
}

/// A provider read through its official API with the person's own key.
///
/// Without a key the provider stays out of sight, like a tool that isn't
/// installed. A rejected key shows as signed out, with the fix in Settings.
/// Any other failure is left to the store, which keeps the last reading and
/// says the refresh failed.
struct APIKeyProvider: UsageProvider {
    let id: ProviderID
    private let keys: any APIKeyStoring
    private let client: APIKeyClient
    private let read: @Sendable (APIKeyClient, String) async throws -> APIKeyReading
    private let now: @Sendable () -> Date

    init(
        id: ProviderID,
        keys: any APIKeyStoring,
        transport: (any HTTPTransport)? = nil,
        now: @escaping @Sendable () -> Date = { .now },
        read: @escaping @Sendable (APIKeyClient, String) async throws -> APIKeyReading
    ) {
        let connection = ProviderCatalog.definition(for: id).apiKey
            // Only catalog providers with a connection reach here; this keeps it total.
            ?? APIKeyConnection(host: "invalid.invalid", keysPage: URL(string: "https://usagenow.com")!)
        self.id = id
        self.keys = keys
        self.client = transport.map { APIKeyClient(connection: connection, transport: $0) } ?? APIKeyClient(connection: connection)
        self.read = read
        self.now = now
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let date = now()
        guard let key = (try? keys.key(for: id)) ?? nil, !key.isEmpty else {
            return .notInstalled(id, at: date)
        }
        do {
            let reading = try await read(client, key)
            return ProviderSnapshot(provider: id, status: .available, windows: reading.windows, balance: reading.balance, updatedAt: date)
        } catch APIKeyClient.Failure.rejectedKey {
            return .notAuthenticated(id, at: date)
        }
    }

    // MARK: Providers

    static func deepSeek(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .deepseek, keys: keys, transport: transport) { client, key in
            try DeepSeekBalance.parse(try await client.get("/user/balance", key: key))
        }
    }

    static func kimi(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .kimi, keys: keys, transport: transport) { client, key in
            try KimiBalance.parse(try await client.get("/v1/users/me/balance", key: key))
        }
    }

    static func openRouter(keys: any APIKeyStoring, transport: (any HTTPTransport)? = nil) -> APIKeyProvider {
        APIKeyProvider(id: .openrouter, keys: keys, transport: transport) { client, key in
            try OpenRouterKey.parse(try await client.get("/api/v1/key", key: key))
        }
    }
}

/// Exact decimals from JSON numbers or strings, without binary rounding noise.
enum APIAmount {
    static func decimal(_ value: Double?) -> Decimal? {
        guard let value, value.isFinite else { return nil }
        return Decimal(string: String(value))
    }

    static func decimal(_ value: String?) -> Decimal? {
        value.flatMap { Decimal(string: $0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// `GET https://api.deepseek.com/user/balance`
///
/// `{"is_available": true, "balance_infos": [{"currency": "CNY",
/// "total_balance": "110.00", "granted_balance": "10.00",
/// "topped_up_balance": "100.00"}]}` — amounts are strings.
enum DeepSeekBalance {
    static func parse(_ data: Data) throws -> APIKeyReading {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw APIKeyClient.Failure.unreadableResponse
        }
        let infos = response.balance_infos ?? []
        // One account can hold both; dollars first, since prices are published in them.
        guard let info = infos.first(where: { $0.currency == "USD" }) ?? infos.first,
              let currency = info.currency,
              let total = APIAmount.decimal(info.total_balance)
        else { throw APIKeyClient.Failure.unreadableResponse }

        return APIKeyReading(balance: AccountBalance(
            currency: currency,
            remaining: total,
            canMakeRequests: response.is_available ?? (total > 0)
        ))
    }

    private struct Response: Decodable {
        struct Info: Decodable {
            var currency: String?
            var total_balance: String?
        }

        var is_available: Bool?
        var balance_infos: [Info]?
    }
}

/// `GET https://api.moonshot.ai/v1/users/me/balance`
///
/// `{"code": 0, "data": {"available_balance": 49.58, "voucher_balance": 46.58,
/// "cash_balance": 3.00}, "status": true}` — keys from platform.moonshot.ai
/// are billed in US dollars.
enum KimiBalance {
    static func parse(_ data: Data) throws -> APIKeyReading {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.status != false,
              let available = APIAmount.decimal(response.data?.available_balance)
        else { throw APIKeyClient.Failure.unreadableResponse }

        return APIKeyReading(balance: AccountBalance(
            currency: "USD",
            remaining: available,
            // Kimi refuses requests once the available balance reaches zero.
            canMakeRequests: available > 0
        ))
    }

    private struct Response: Decodable {
        struct Balance: Decodable {
            var available_balance: Double?
        }

        var status: Bool?
        var data: Balance?
    }
}

/// `GET https://openrouter.ai/api/v1/key`
///
/// Spending in OpenRouter credits, which are US dollars, for today, this
/// week, and this month, plus the key's own limit when one is set.
enum OpenRouterKey {
    static func parse(_ data: Data) throws -> APIKeyReading {
        guard let key = try? JSONDecoder().decode(Response.self, from: data).data else {
            throw APIKeyClient.Failure.unreadableResponse
        }

        var windows: [UsageWindow] = []
        let remaining = APIAmount.decimal(key.limit_remaining)
        if let limit = key.limit, limit > 0, let left = key.limit_remaining,
           let kind = windowKind(key.limit_reset) {
            windows.append(UsageWindow(kind: kind, usage: UsagePercentage(used: limit - left, limit: limit)))
        }

        return APIKeyReading(
            balance: AccountBalance(
                currency: "USD",
                remaining: remaining,
                spentToday: APIAmount.decimal(key.usage_daily),
                spentThisMonth: APIAmount.decimal(key.usage_monthly),
                canMakeRequests: remaining.map { $0 > 0 } ?? true
            ),
            windows: windows
        )
    }

    /// A limit without a reset is a lifetime cap, which isn't a window; its
    /// remainder still shows as the balance.
    static func windowKind(_ reset: String?) -> UsageWindowKind? {
        switch reset?.lowercased() {
        case "daily": .custom(minutes: 24 * 60)
        case "weekly": .weekly
        case "monthly": .monthly
        default: nil
        }
    }

    private struct Response: Decodable {
        struct Key: Decodable {
            var limit: Double?
            var limit_remaining: Double?
            var limit_reset: String?
            var usage_daily: Double?
            var usage_monthly: Double?
        }

        var data: Key?
    }
}
