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
    }

    static let timeout: TimeInterval = 15

    let connection: APIKeyConnection
    let transport: any HTTPTransport

    init(connection: APIKeyConnection, transport: any HTTPTransport = APIKeyTransport.shared) {
        self.connection = connection
        self.transport = transport
    }

    func get(_ path: String, key: String) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = connection.host
        components.path = path
        guard let url = components.url, url.scheme == "https", url.host == connection.host else {
            throw Failure.refusedDestination
        }

        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageNow/\(AppInfo.version) (https://usagenow.com)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.send(request)
        // A response from anywhere else means the request was redirected.
        guard response.url?.host == nil || response.url?.host == connection.host else {
            throw Failure.refusedDestination
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw Failure.rejectedKey
        default: throw Failure.unexpectedStatus(response.statusCode)
        }
    }
}

/// An ephemeral session that refuses every redirect.
final class APIKeyTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = APIKeyTransport()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = APIKeyClient.timeout
        configuration.timeoutIntervalForResource = APIKeyClient.timeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLSessionTransport.TransportError.notHTTP }
        return (data, http)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
