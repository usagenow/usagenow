import Foundation
import Security

/// EXPERIMENTAL — off unless the user turns on "Fetch Claude usage limits".
///
/// Claude Code doesn't store subscription limits locally. Its `/usage`
/// command reads them from Anthropic's undocumented endpoint
/// `GET https://api.anthropic.com/api/oauth/usage`, authenticated with the
/// Claude Code OAuth access token from the login keychain
/// (`Claude Code-credentials`). This client does the same.
///
/// Guarantees:
/// - The keychain is only read after the feature is enabled.
/// - The access token stays in memory. It's never persisted, logged,
///   refreshed, or modified, and it's sent only to api.anthropic.com.
/// - Results are cached; automatic refreshes query at most every 5 minutes,
///   and only one request runs at a time.
/// - A failure never blanks the display: the last good values stay for a
///   day, shown as stale. Local activity keeps working regardless.
/// - After a keychain read fails (access denied, no sign-in, expired
///   sign-in), automatic refreshes don't read the keychain again — so macOS
///   doesn't keep asking. A manual refresh or re-enabling tries again.
actor ClaudeUsageLimitsClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    enum ClientError: Error {
        case rateLimited
        case unexpectedStatus(Int)
    }

    private(set) var availability: ClaudeQuotaAvailability = .disabled

    private let credentials: any ClaudeCredentialSource
    private let transport: any HTTPTransport
    private let cache: QuotaCache<[UsageWindow]>
    /// Asks Claude Code to renew its own sign-in. UsageNow never does it itself.
    private let requestSignInRefresh: (@Sendable () async -> Bool)?
    private let refreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var token: ClaudeOAuthToken?
    private var lastSignInRefresh: Date?
    private var keychainNeedsManualRetry = false

    init(
        credentials: any ClaudeCredentialSource = KeychainClaudeCredentialSource(),
        transport: any HTTPTransport = URLSessionTransport.ephemeral(timeout: 10),
        minimumInterval: TimeInterval = 5 * 60,
        signInRefreshInterval: TimeInterval = ClaudeSignInRefresher.minimumInterval,
        requestSignInRefresh: (@Sendable () async -> Bool)? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.credentials = credentials
        self.transport = transport
        self.cache = QuotaCache(minimumInterval: minimumInterval, retention: 24 * 60 * 60)
        self.requestSignInRefresh = requestSignInRefresh
        self.refreshInterval = signInRefreshInterval
        self.now = now
    }

    /// Cached or freshly fetched windows, or `nil` when unavailable.
    func windows(trigger: RefreshTrigger, now: @escaping @Sendable () -> Date) async -> QuotaCache<[UsageWindow]>.Entry? {
        if trigger == .manual { keychainNeedsManualRetry = false }
        return await cache.value(trigger: trigger, now: now) { [self] in
            try await self.fetch(now: now())
        }
    }

    /// Forgets the token, cached limits, and status, e.g. when the feature is turned off.
    func reset() async {
        token = nil
        keychainNeedsManualRetry = false
        update(.disabled)
        await cache.clear()
    }

    private func fetch(now: Date) async throws -> QuotaFetchResult<[UsageWindow]> {
        guard let token = try await validToken(at: now) else { return .unavailable }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageNow/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            update(.endpointUnavailable)
            throw error
        }
        Log.provider.info("Claude usage limits: HTTP \(response.statusCode, privacy: .public)")

        switch response.statusCode {
        case 200:
            guard let windows = ClaudeUsageLimitsParser.windows(from: data) else {
                update(.unsupportedResponse)
                return .unavailable
            }
            update(.available)
            return .value(windows)
        case 401, 403:
            // Rejected. Claude Code renews its own credential when it runs;
            // UsageNow never does. Read the keychain again after a manual refresh.
            self.token = nil
            keychainNeedsManualRetry = true
            update(.staleAuthentication)
            return .unavailable
        case 404:
            update(.endpointUnavailable)
            return .unavailable
        case 429:
            update(.endpointUnavailable)
            throw ClientError.rateLimited
        default:
            update(.endpointUnavailable)
            throw ClientError.unexpectedStatus(response.statusCode)
        }
    }

    /// The in-memory token, re-reading the keychain only when it's missing or
    /// expired. An expired sign-in is handed back to Claude Code to renew,
    /// then read once more.
    private func validToken(at now: Date) async throws -> ClaudeOAuthToken? {
        if let cached = token, !cached.isExpired(at: now) { return cached }
        token = nil
        guard !keychainNeedsManualRetry else { return nil }

        switch try await credentials.lookup() {
        case .found(let found) where !found.isExpired(at: now):
            token = found
            return found
        case .found(let expired):
            let expiry = expired.expiresAt?.formatted(.iso8601) ?? "unknown"
            Log.provider.notice("Claude usage limits: keychain sign-in expired at \(expiry, privacy: .public)")
            return try await renewedToken(at: now)
        case .notFound:
            return try await renewedToken(at: now)
        case .accessDenied:
            fail(with: .keychainDenied)
            return nil
        }
    }

    /// Lets Claude Code renew its credential, then reads the keychain again.
    /// Rate-limited, and gives up quietly when the CLI isn't there or didn't help.
    private func renewedToken(at now: Date) async throws -> ClaudeOAuthToken? {
        guard let requestSignInRefresh else {
            fail(with: .staleAuthentication)
            return nil
        }
        if let lastSignInRefresh, now.timeIntervalSince(lastSignInRefresh) < refreshInterval {
            fail(with: .staleAuthentication)
            return nil
        }
        lastSignInRefresh = now

        guard await requestSignInRefresh() else {
            fail(with: .staleAuthentication)
            return nil
        }
        guard case .found(let renewed) = try await credentials.lookup(), !renewed.isExpired(at: self.now()) else {
            fail(with: .staleAuthentication)
            return nil
        }
        token = renewed
        return renewed
    }

    private func fail(with availability: ClaudeQuotaAvailability) {
        keychainNeedsManualRetry = true
        update(availability)
    }

    private func update(_ newAvailability: ClaudeQuotaAvailability) {
        guard newAvailability != availability else { return }
        availability = newAvailability
        Log.provider.notice("Claude usage limits: \(String(describing: newAvailability), privacy: .public)")
    }
}

/// Why Claude quota is or isn't available, in detail. Kept for logs and
/// diagnosis; the UI shows the shorter `QuotaUnavailableReason`.
enum ClaudeQuotaAvailability: Sendable, Equatable {
    case available
    /// The experimental setting is off, or Claude Code isn't tracked.
    case disabled
    /// No saved sign-in, or it expired or was rejected. Claude Code renews
    /// it when it runs in Terminal; UsageNow never does.
    case staleAuthentication
    case keychainDenied
    /// Anthropic's usage endpoint didn't answer, or answered with an error.
    case endpointUnavailable
    /// The endpoint answered in a shape UsageNow doesn't understand.
    case unsupportedResponse

    /// What the user is told. Several internal cases share one plain message.
    var unavailableReason: QuotaUnavailableReason? {
        switch self {
        case .available, .disabled: nil
        case .staleAuthentication: .signInExpired
        case .keychainDenied: .permissionDenied
        case .endpointUnavailable, .unsupportedResponse: .temporarilyUnavailable
        }
    }
}

/// An OAuth access token held in memory only.
struct ClaudeOAuthToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let value: String
    let expiresAt: Date?

    func isExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }

    // Never reveal the token through string interpolation or debugging output.
    var description: String { "ClaudeOAuthToken(<redacted>)" }
    var debugDescription: String { description }
}

enum ClaudeCredentialLookup: Sendable {
    case found(ClaudeOAuthToken)
    /// No Claude Code sign-in in the keychain.
    case notFound
    /// The user denied access or dismissed the keychain prompt.
    case accessDenied
}

protocol ClaudeCredentialSource: Sendable {
    func lookup() async throws -> ClaudeCredentialLookup
}

/// Reads Claude Code's OAuth credential from the login keychain with the
/// Security framework. macOS asks the user to allow access the first time.
/// Only the access token and its expiry are extracted; the refresh token
/// is never read into a variable.
struct KeychainClaudeCredentialSource: ClaudeCredentialSource {
    static let service = "Claude Code-credentials"

    func lookup() async throws -> ClaudeCredentialLookup {
        // The keychain may show an access prompt; wait off the concurrency pool.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.read() })
            }
        }
    }

    private static func read() throws -> ClaudeCredentialLookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = ClaudeCredentialParser.token(from: data) else { return .notFound }
            return .found(token)
        case errSecItemNotFound:
            return .notFound
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            Log.provider.info("Claude usage limits: keychain access not granted (\(status, privacy: .public))")
            return .accessDenied
        default:
            throw KeychainStore.KeychainError.unexpectedStatus(status)
        }
    }
}

enum ClaudeCredentialParser {
    /// Extracts `claudeAiOauth.accessToken` and `expiresAt` (epoch milliseconds).
    static func token(from data: Data) -> ClaudeOAuthToken? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty else { return nil }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return ClaudeOAuthToken(value: accessToken, expiresAt: expiresAt)
    }
}

/// Parses the usage endpoint's response defensively.
///
/// Each top-level entry with a numeric `utilization` (percent) is a window.
/// Its length comes from the key: `five_hour` → 5 hours, `seven_day` →
/// 7 days. A model-family suffix (`seven_day_opus`) becomes the window's
/// scope. Entries with unknown keys, null utilization, or other shapes
/// (such as `extra_usage`) are skipped rather than guessed at.
enum ClaudeUsageLimitsParser {
    private static let numberWords = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "ten": 10, "twelve": 12, "fourteen": 14, "thirty": 30,
    ]
    private static let unitMinutes = ["hour": 60, "hours": 60, "day": 24 * 60, "days": 24 * 60]
    private static let knownScopes = ["opus": "Opus", "sonnet": "Sonnet", "haiku": "Haiku"]

    static func windows(from data: Data) -> [UsageWindow]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let windows = object.compactMap { key, value -> UsageWindow? in
            guard let entry = value as? [String: Any],
                  let utilization = (entry["utilization"] as? NSNumber)?.doubleValue,
                  let (kind, scope) = window(forKey: key) else { return nil }
            return UsageWindow(
                kind: kind,
                scope: scope,
                usage: UsagePercentage(percent: utilization),
                resetsAt: SessionTimestamp.parse(entry["resets_at"] as? String)
            )
        }
        return windows.sortedForDisplay()
    }

    static func window(forKey key: String) -> (UsageWindowKind, String?)? {
        let parts = key.lowercased().split(separator: "_").map(String.init)
        guard parts.count >= 2,
              let count = numberWords[parts[0]] ?? Int(parts[0]),
              let unit = unitMinutes[parts[1]] else { return nil }
        let kind = UsageWindowKind(durationMinutes: count * unit)
        switch parts.count {
        case 2: return (kind, nil)
        case 3: return knownScopes[parts[2]].map { (kind, $0) }
        default: return nil
        }
    }
}
