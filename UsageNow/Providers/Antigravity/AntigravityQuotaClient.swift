import Foundation

/// EXPERIMENTAL — off unless the user turns on "Fetch Antigravity usage limits".
///
/// Antigravity CLI shows its limits only in an interactive `/usage` panel and
/// keeps no copy on disk. It reads them from Google's undocumented Cloud
/// Code endpoint `v1internal:retrieveUserQuotaSummary` with the Google sign-in
/// it saved in the login keychain; this client does the same.
///
/// Guarantees, matching the Claude usage limits source:
/// - The keychain is only read after the feature is enabled, and through
///   `/usr/bin/security`, which the item already trusts — no prompt.
/// - The access token stays in memory. It's never persisted, logged,
///   refreshed, or modified, and it's sent only to Google's Cloud Code host.
///   The refresh token is never used.
/// - Google access tokens last about an hour and `agy` renews its own only
///   while it runs. An expired sign-in isn't read again until `agy` saves a
///   new one; its modification date is checked without the secret.
/// - Results are cached; automatic refreshes query at most every 5 minutes,
///   one request at a time. The last good values stay for a day, marked
///   stale, across relaunches when a store is given.
actor AntigravityQuotaClient {
    static let endpoint = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!

    enum ClientError: Error {
        case rateLimited
        case unexpectedStatus(Int)
    }

    private enum KeychainHold: Equatable {
        case none
        /// The sign-in couldn't be read; only a manual refresh tries again.
        case denied
        /// The saved sign-in was unusable; wait until its modification date changes.
        case untilChanged(since: Date?)
    }

    private(set) var availability: QuotaSourceAvailability = .disabled

    private let credentials: any CredentialSource
    private let transport: any HTTPTransport
    private let cache: QuotaCache<[UsageWindow]>
    private var token: OAuthAccessToken?
    private var keychainHold = KeychainHold.none

    init(
        credentials: any CredentialSource = KeychainAntigravityCredentialSource(),
        transport: any HTTPTransport = URLSessionTransport.ephemeral(timeout: 10),
        minimumInterval: TimeInterval = 5 * 60,
        lastKnownLimits: QuotaCacheStore<[UsageWindow]>? = nil
    ) {
        self.credentials = credentials
        self.transport = transport
        self.cache = QuotaCache(minimumInterval: minimumInterval, retention: 24 * 60 * 60, store: lastKnownLimits)
    }

    /// Cached or freshly fetched windows, or `nil` when unavailable.
    func windows(trigger: RefreshTrigger, now: @escaping @Sendable () -> Date) async -> QuotaCache<[UsageWindow]>.Entry? {
        if trigger == .manual { keychainHold = .none }
        return await cache.value(trigger: trigger, now: now) { [self] in
            try await self.fetch(now: now())
        }
    }

    /// Forgets the token, cached limits, and status, e.g. when the feature is turned off.
    func reset() async {
        token = nil
        keychainHold = .none
        update(.disabled)
        await cache.clear()
    }

    private func fetch(now: Date) async throws -> QuotaFetchResult<[UsageWindow]> {
        guard let token = try await validToken(at: now) else { return .unavailable }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageNow/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        // No project: the one agy caches names its own workspace, not a
        // Cloud Code project, and Google rejects the request with it.
        request.httpBody = Data("{}".utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            update(.endpointUnavailable)
            throw error
        }
        if response.statusCode != 200 {
            // Google's error code and reason only — never the message, which can name the account.
            Log.provider.notice("Antigravity usage limits: HTTP \(response.statusCode, privacy: .public) \(GoogleAPIError.summary(of: data), privacy: .public)")
        }

        switch response.statusCode {
        case 200:
            guard let windows = AntigravityQuotaParser.windows(from: data) else {
                update(.unsupportedResponse)
                return .unavailable
            }
            update(.available)
            return .value(windows)
        case 401:
            // Rejected or expired early. `agy` renews its own sign-in; UsageNow never does.
            self.token = nil
            await waitForNewSignIn()
            return .unavailable
        case 403, 404:
            // The sign-in is fine but the request isn't allowed or understood;
            // a new sign-in wouldn't change that, so don't wait for one.
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

    /// The in-memory token, re-reading the keychain only when it's missing,
    /// expired, or has changed since it was found unusable.
    private func validToken(at now: Date) async throws -> OAuthAccessToken? {
        if let cached = token, !cached.isExpired(at: now) { return cached }
        token = nil

        switch keychainHold {
        case .none:
            break
        case .denied:
            return nil
        case .untilChanged(let since):
            guard await credentials.lastModified() != since else { return nil }
            keychainHold = .none
            Log.provider.notice("Antigravity usage limits: the saved sign-in changed; reading it again")
        }

        switch try await credentials.lookup() {
        case .found(let found) where !found.isExpired(at: now):
            token = found
            return found
        case .found(let expired):
            let expiry = expired.expiresAt?.formatted(.iso8601) ?? "unknown"
            Log.provider.notice("Antigravity usage limits: saved sign-in expired at \(expiry, privacy: .public)")
            await waitForNewSignIn()
            return nil
        case .notFound:
            await waitForNewSignIn()
            return nil
        case .accessDenied:
            keychainHold = .denied
            update(.keychainDenied)
            return nil
        }
    }

    private func waitForNewSignIn() async {
        keychainHold = .untilChanged(since: await credentials.lastModified())
        update(.staleAuthentication)
    }

    private func update(_ newAvailability: QuotaSourceAvailability) {
        guard newAvailability != availability else { return }
        availability = newAvailability
        Log.provider.notice("Antigravity usage limits: \(String(describing: newAvailability), privacy: .public)")
    }
}

/// The loggable part of a Google API error: `error.status` and the first
/// `details[].reason`, e.g. "PERMISSION_DENIED/SERVICE_DISABLED".
enum GoogleAPIError {
    static func summary(of data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return "(no error details)" }
        let status = error["status"] as? String ?? "unknown"
        let reason = (error["details"] as? [[String: Any]])?.lazy.compactMap { $0["reason"] as? String }.first
        return reason.map { "\(status)/\($0)" } ?? status
    }
}

/// Reads the Google sign-in `agy` saved in the login keychain, through the
/// `security` tool it was saved with. Only the access token and its expiry
/// are kept.
struct KeychainAntigravityCredentialSource: CredentialSource {
    static let timeout: TimeInterval = 60

    func lookup() async throws -> CredentialLookup {
        let result = await SecurityTool.readPassword(service: AntigravityEnvironment.keychainService, account: nil, timeout: Self.timeout)
        return Self.lookup(exitStatus: result.exitStatus, output: result.output)
    }

    static func lookup(exitStatus: Int32, output: Data) -> CredentialLookup {
        switch exitStatus {
        case 0:
            if let token = AntigravityTokenParser.token(from: output) { return .found(token) }
            // Names only — which format was found and its field names, never values.
            Log.provider.notice("Antigravity usage limits: unrecognized sign-in format: \(AntigravityTokenParser.shape(of: output), privacy: .public)")
            return .notFound
        case SecurityTool.itemNotFoundStatus:
            return .notFound
        default:
            Log.provider.info("Antigravity usage limits: the security tool exited with \(exitStatus, privacy: .public)")
            return .accessDenied
        }
    }

    func lastModified() async -> Date? {
        KeychainItem.modificationDate(service: AntigravityEnvironment.keychainService)
    }
}

/// Extracts an access token and its expiry from what `agy` saved.
///
/// Go keyring libraries may wrap the value (`go-keyring-base64:` or
/// `go-keyring-encoded:`), and OAuth libraries name fields differently, so a
/// few common spellings are accepted. The refresh token is never read into
/// a variable.
enum AntigravityTokenParser {
    private static let base64Prefix = "go-keyring-base64:"
    private static let hexPrefix = "go-keyring-encoded:"
    private static let accessTokenKeys = ["access_token", "accessToken"]
    private static let expiryKeys = ["expiry", "expiry_date", "expiryDate", "expires_at", "expiresAt"]
    private static let containerKeys = ["token", "tokens", "oauth", "credentials", "credential"]

    static func token(from data: Data) -> OAuthAccessToken? {
        let payload = unwrapped(data)
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        for candidate in [object] + containerKeys.compactMap({ object[$0] as? [String: Any] }) {
            guard let value = accessTokenKeys.lazy.compactMap({ candidate[$0] as? String }).first, !value.isEmpty else { continue }
            let expiry = expiryKeys.lazy.compactMap { date(from: candidate[$0]) }.first
            return OAuthAccessToken(value: value, expiresAt: expiry)
        }
        return nil
    }

    /// A description safe to log: the wrapping and top-level field names.
    static func shape(of data: Data) -> String {
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapping = [base64Prefix, hexPrefix].first { raw.hasPrefix($0) } ?? "none"
        guard let object = try? JSONSerialization.jsonObject(with: unwrapped(data)) as? [String: Any] else {
            return "wrapping \(wrapping), not a JSON object"
        }
        return "wrapping \(wrapping), keys \(object.keys.sorted().joined(separator: ","))"
    }

    private static func unwrapped(_ data: Data) -> Data {
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix(base64Prefix) {
            return Data(base64Encoded: String(raw.dropFirst(base64Prefix.count))) ?? Data()
        }
        if raw.hasPrefix(hexPrefix) {
            return hexData(String(raw.dropFirst(hexPrefix.count))) ?? Data()
        }
        return Data(raw.utf8)
    }

    /// RFC 3339 strings (Go's `time.Time`), or epoch seconds or milliseconds.
    static func date(from value: Any?) -> Date? {
        switch value {
        case let string as String:
            if let date = SessionTimestamp.parse(string) { return date }
            return Double(string).flatMap { epochDate($0) }
        case let number as NSNumber:
            return epochDate(number.doubleValue)
        default:
            return nil
        }
    }

    private static func epochDate(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 1e12 ? value / 1000 : value)
    }

    private static func hexData(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

/// Parses `retrieveUserQuotaSummary` defensively.
///
/// The summary lists groups of models ("Gemini Models", "Claude and GPT
/// Models") that share limits, each with buckets such as a weekly limit.
/// A bucket becomes a window only when its length can be read from its
/// identifier or name and it states a remaining fraction; the group's name
/// becomes the window's scope. Anything else is skipped rather than guessed.
enum AntigravityQuotaParser {
    static func windows(from data: Data) -> [UsageWindow]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let summary = object["quotaSummary"] as? [String: Any] ?? object["response"] as? [String: Any] ?? object
        guard let groups = summary["groups"] as? [[String: Any]] else { return nil }

        var windows: [UsageWindow] = []
        for group in groups {
            let scope = scopeName(group["displayName"] as? String)
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard (bucket["disabled"] as? Bool) != true else { continue }
                let remaining = bucket["remaining"] as? [String: Any] ?? [:]
                guard let fraction = number(bucket["remainingFraction"] ?? remaining["remainingFraction"]),
                      let kind = kind(for: [bucket["bucketId"], bucket["displayName"]].compactMap { $0 as? String }.joined(separator: " ")) else { continue }
                windows.append(UsageWindow(
                    kind: kind,
                    scope: scope,
                    usage: UsagePercentage(percent: (1 - min(max(fraction, 0), 1)) * 100),
                    resetsAt: AntigravityTokenParser.date(from: bucket["resetTime"] ?? remaining["resetTime"])
                ))
            }
        }
        return windows.sortedForDisplay()
    }

    /// "Gemini Models" → "Gemini"; "Claude and GPT Models" → "Claude and GPT".
    static func scopeName(_ displayName: String?) -> String? {
        guard var name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if name.lowercased().hasSuffix(" models") { name = String(name.dropLast(" models".count)) }
        return name.isEmpty ? nil : name
    }

    /// The window length a bucket names, e.g. "weekly", "daily", "5-hour", "5h".
    static func kind(for text: String) -> UsageWindowKind? {
        let lowered = text.lowercased()
        if lowered.contains("week") { return .weekly }
        if lowered.contains("daily") || lowered.contains("24h") { return UsageWindowKind(durationMinutes: 24 * 60) }
        if let hours = firstNumber(in: lowered, before: ["-hour", " hour", "hour", "h"]) { return UsageWindowKind(durationMinutes: hours * 60) }
        return nil
    }

    private static func firstNumber(in text: String, before units: [String]) -> Int? {
        for unit in units {
            guard let range = text.range(of: "(\\d+)\(NSRegularExpression.escapedPattern(for: unit))\\b", options: .regularExpression) else { continue }
            let digits = text[range].prefix { $0.isNumber }
            if let value = Int(digits), value > 0 { return value }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }
}
