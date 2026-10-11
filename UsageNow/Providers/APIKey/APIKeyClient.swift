import Foundation

/// Sends one read-only request, with the person's API key, to the one host
/// the provider's catalog entry names.
///
/// Three rules hold for every request:
/// - It goes to `connection.host` over HTTPS, or it isn't sent.
/// - Redirects aren't followed, so a response can't carry the key's header
///   to another address.
/// - Neither the key nor the response body is logged.
struct APIKeyClient: Sendable {
    enum Failure: Error, Equatable {
        /// The URL wasn't HTTPS on the provider's own host.
        case refusedDestination
        /// The provider rejected the key: missing, revoked, or wrong.
        case rejectedKey
        case unexpectedStatus(Int)
        case unreadableResponse
        /// Malformed input, such as a newline in a header credential.
        case invalidCredential
        case permissionDenied
        case rateLimited(until: Date)
    }

    static let timeout: TimeInterval = 15

    let connection: APIKeyConnection
    let transport: any HTTPTransport
    let cooldown: APIRequestCooldown

    init(connection: APIKeyConnection, transport: any HTTPTransport = APIKeyTransport.shared,
         cooldown: APIRequestCooldown = .shared) {
        self.connection = connection
        self.transport = transport
        self.cooldown = cooldown
    }

    func get(_ path: String, key: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = connection.host
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url, url.scheme == "https", url.host == connection.host else {
            throw Failure.refusedDestination
        }

        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        guard !key.isEmpty, key.utf8.count <= 32_768,
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw Failure.invalidCredential
        }
        var normalizedCredential = key
        switch connection.authentication {
        case .bearer:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .elevenLabs:
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
        case .githubToken:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        case .cursorSession, .perplexitySession:
            let cookie = try SessionCookie.normalized(key, allowedNames: connection.authentication.cookieNames)
            normalizedCredential = cookie
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.setValue("https://\(connection.host)", forHTTPHeaderField: "Origin")
            request.setValue(connection.keysPage.absoluteString, forHTTPHeaderField: "Referer")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageNow/\(AppInfo.version) (https://usagenow.com)", forHTTPHeaderField: "User-Agent")

        try Task.checkCancellation()
        try await cooldown.check(host: connection.host, credential: normalizedCredential)
        let (data, response) = try await transport.send(request)
        // A response from anywhere else means the request was redirected.
        guard response.url?.scheme == "https", response.url?.host == connection.host,
              response.url?.port == nil || response.url?.port == 443 else {
            throw Failure.refusedDestination
        }
        switch response.statusCode {
        case 200..<300: return data
        case 429:
            let until = await cooldown.record(host: connection.host, credential: normalizedCredential,
                                              retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
            throw Failure.rateLimited(until: until)
        case 401, 403:
            if connection.authentication == .elevenLabs,
               let error = try? JSONDecoder().decode(ProviderAccessError.self, from: data),
               error.isPermissionDenied {
                throw Failure.permissionDenied
            }
            throw Failure.rejectedKey
        default: throw Failure.unexpectedStatus(response.statusCode)
        }
    }
}

private struct ProviderAccessError: Decodable {
    struct Detail: Decodable { var code: String?; var status: String? }
    var detail: Detail
    var isPermissionDenied: Bool {
        let denied = Set(["missing_permissions", "insufficient_permissions"])
        return denied.contains(detail.code ?? "") || denied.contains(detail.status ?? "")
    }
}

/// Keep only the selected service's session cookie. A copied Cookie
/// header often also contains analytics cookies that UsageNow doesn't need.
enum SessionCookie {
    static func normalized(_ input: String, allowedNames: [String]) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 32_768,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw APIKeyClient.Failure.invalidCredential
        }
        if value.lowercased().hasPrefix("cookie:") { value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        var cookies: [String: String] = [:]
        for part in value.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespaces)
            let content = pair[1].trimmingCharacters(in: .whitespaces)
            guard allowedNames.contains(where: { name == $0 || name.hasPrefix($0 + ".") }) else { continue }
            guard !content.isEmpty, cookies[name] == nil else { throw APIKeyClient.Failure.invalidCredential }
            guard content.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7f && ![0x22, 0x2c, 0x5c].contains($0.value) }) else {
                throw APIKeyClient.Failure.invalidCredential
            }
            cookies[name] = content
        }
        for name in allowedNames {
            let chunks = cookies.keys.filter { $0.hasPrefix(name + ".") }
            if let value = cookies[name] {
                guard chunks.isEmpty else { throw APIKeyClient.Failure.invalidCredential }
                return "\(name)=\(value)"
            }
            if !chunks.isEmpty {
                guard chunks.count <= 16 else { throw APIKeyClient.Failure.invalidCredential }
                let ordered = (0..<chunks.count).map { "\(name).\($0)" }
                guard ordered.allSatisfy({ cookies[$0] != nil }) else { throw APIKeyClient.Failure.invalidCredential }
                return ordered.map { "\($0)=\(cookies[$0]!)" }.joined(separator: "; ")
            }
        }
        // Require a named cookie instead of guessing which of several
        // authentication systems issued a bare token.
        throw APIKeyClient.Failure.invalidCredential
    }
}

/// An ephemeral session that refuses every redirect.
///
/// The session is made once, in `init`: providers connected with a key all
/// refresh at the same time through `shared`, and a lazily created session
/// could be created by two of them at once.
final class APIKeyTransport: HTTPTransport, Sendable {
    static let shared = APIKeyTransport()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = APIKeyClient.timeout
        configuration.timeoutIntervalForResource = APIKeyClient.timeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLSessionTransport.TransportError.notHTTP }
        return (data, http)
    }
}

/// Answers every redirect with "don't follow", so a key's header can't be
/// carried to another host.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
