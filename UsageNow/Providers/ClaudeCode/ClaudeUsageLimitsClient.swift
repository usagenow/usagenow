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
///   day, shown as stale — across relaunches too, when a store is given.
///   Local activity keeps working regardless.
/// - An expired, missing, or rejected sign-in isn't read again until it
///   changes. Its modification date is read without the secret, so waiting
///   never shows a keychain prompt, and a sign-in Claude Code renews is
///   picked up on the next automatic refresh.
/// - After keychain access is denied, only a manual refresh or re-enabling
///   asks again, so macOS doesn't keep prompting.
actor ClaudeUsageLimitsClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    enum ClientError: Error {
        case rateLimited
        case unexpectedStatus(Int)
    }

    /// Why the keychain isn't read during automatic refreshes right now.
    private enum KeychainHold: Equatable {
        /// Read it whenever a token is needed.
        case none
        /// Access was denied; only a manual refresh asks again.
        case denied
        /// The saved sign-in was unusable. Reading it again would give the
        /// same answer, so wait until its modification date changes.
        case untilChanged(since: Date?)
    }

    private(set) var availability: QuotaSourceAvailability = .disabled

    private let credentials: any CredentialSource
    private let transport: any HTTPTransport
    private let cache: QuotaCache<[UsageWindow]>
    /// Asks Claude Code to renew its own sign-in. UsageNow never does it itself.
    private let requestSignInRefresh: (@Sendable () async -> Bool)?
    private let refreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var token: OAuthAccessToken?
    private var lastSignInRefresh: Date?
    private var keychainHold = KeychainHold.none

    init(
        credentials: any CredentialSource = KeychainClaudeCredentialSource(),
        transport: any HTTPTransport = URLSessionTransport.ephemeral(timeout: 10),
        minimumInterval: TimeInterval = 5 * 60,
        lastKnownLimits: QuotaCacheStore<[UsageWindow]>? = nil,
        signInRefreshInterval: TimeInterval = ClaudeSignInRefresher.minimumInterval,
        requestSignInRefresh: (@Sendable () async -> Bool)? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.credentials = credentials
        self.transport = transport
        self.cache = QuotaCache(minimumInterval: minimumInterval, retention: 24 * 60 * 60, store: lastKnownLimits)
        self.requestSignInRefresh = requestSignInRefresh
        self.refreshInterval = signInRefreshInterval
        self.now = now
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
            // UsageNow never does. Wait for the saved sign-in to change.
            self.token = nil
            await waitForNewSignIn()
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
            Log.provider.notice("Claude usage limits: the Claude Code sign-in changed; reading it again")
        }

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
            keychainHold = .denied
            update(.keychainDenied)
            return nil
        }
    }

    /// Lets Claude Code renew its credential, then reads the keychain again.
    /// Rate-limited; when the CLI isn't there or didn't help, waits for the
    /// sign-in to change instead.
    private func renewedToken(at now: Date) async throws -> OAuthAccessToken? {
        let mayAsk = lastSignInRefresh.map { now.timeIntervalSince($0) >= refreshInterval } ?? true
        if let requestSignInRefresh, mayAsk {
            lastSignInRefresh = now
            if await requestSignInRefresh(),
               case .found(let renewed) = try await credentials.lookup(),
               !renewed.isExpired(at: self.now()) {
                token = renewed
                return renewed
            }
        }
        await waitForNewSignIn()
        return nil
    }

    /// Stops reading the keychain until Claude Code saves a different sign-in.
    private func waitForNewSignIn() async {
        keychainHold = .untilChanged(since: await credentials.lastModified())
        update(.staleAuthentication)
    }

    private func update(_ newAvailability: QuotaSourceAvailability) {
        guard newAvailability != availability else { return }
        availability = newAvailability
        Log.provider.notice("Claude usage limits: \(String(describing: newAvailability), privacy: .public)")
    }
}

/// Reads Claude Code's OAuth credential from the login keychain.
///
/// The token is read the way Claude Code reads it itself: with
/// `/usr/bin/security find-generic-password -w`. Claude Code saves the item
/// through that tool, and every save resets the item's per-app permissions,
/// so reading it with the Security framework would ask for the login
/// password again after each renewal — "Always Allow" doesn't survive one.
/// Turning on "Fetch Claude usage limits" is the consent.
///
/// The output goes through a pipe straight into memory: nothing is written
/// to disk or logged, and only the access token and its expiry are kept.
struct KeychainClaudeCredentialSource: CredentialSource {
    static let service = "Claude Code-credentials"
    /// Long enough for someone to answer a prompt, should one ever appear.
    static let timeout: TimeInterval = 60
    static let itemNotFoundStatus = SecurityTool.itemNotFoundStatus

    func lookup() async throws -> CredentialLookup {
        let result = await SecurityTool.readPassword(service: Self.service, account: NSUserName(), timeout: Self.timeout)
        return Self.lookup(exitStatus: result.exitStatus, output: result.output)
    }

    /// Interprets what `security find-generic-password -w` returned.
    static func lookup(exitStatus: Int32, output: Data) -> CredentialLookup {
        switch exitStatus {
        case 0:
            return ClaudeCredentialParser.token(from: output).map(CredentialLookup.found) ?? .notFound
        case itemNotFoundStatus:
            return .notFound
        default:
            Log.provider.info("Claude usage limits: the security tool exited with \(exitStatus, privacy: .public)")
            return .accessDenied
        }
    }

    func lastModified() async -> Date? {
        KeychainItem.modificationDate(service: Self.service)
    }
}

enum ClaudeCredentialParser {
    /// Extracts `claudeAiOauth.accessToken` and `expiresAt` (epoch milliseconds).
    static func token(from data: Data) -> OAuthAccessToken? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty else { return nil }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return OAuthAccessToken(value: accessToken, expiresAt: expiresAt)
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
