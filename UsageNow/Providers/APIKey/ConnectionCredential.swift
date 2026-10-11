import Foundation

extension APIKeyConnection {
    func normalizedCredential(_ input: String) throws -> String {
        if authentication.isSession {
            return try SessionCookie.normalized(input, allowedNames: authentication.cookieNames)
        }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 32_768,
              !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains) else {
            throw APIKeyClient.Failure.invalidCredential
        }
        return value
    }

    var credentialTitle: LocalizedStringResource {
        switch authentication {
        case .cursorSession, .perplexitySession: "Session cookie"
        case .githubToken: "GitHub token"
        default: "API key"
        }
    }

    func statusTitle(saved: Bool) -> LocalizedStringResource {
        switch authentication {
        case .cursorSession, .perplexitySession: saved ? "Session saved" : "Not connected"
        case .githubToken: saved ? "Token saved" : "Not connected"
        default: saved ? "API key saved" : "No API key yet"
        }
    }
}

/// Only cookies belonging to the service and applicable to its usage URL
/// may leave the ephemeral login window. No identity/analytics cookies.
enum LoginCookieSelection {
    static func select(_ cookies: [HTTPCookie], connection: APIKeyConnection, now: Date = .now) throws -> String {
        let endpoint = connection.authentication == .cursorSession ? "/api/usage-summary" : "/rest/billing/credits"
        let selected = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            // Limit parent-domain matching to the actual registrable service
            // domain. Cookies scoped to .com or a lookalike are never sent.
            let domains = connection.authentication == .cursorSession ? ["cursor.com"] : ["perplexity.ai", "www.perplexity.ai"]
            let path = cookie.path
            let pathMatches = endpoint == path || (endpoint.hasPrefix(path) && (path.hasSuffix("/") || endpoint.dropFirst(path.count).hasPrefix("/")))
            return domains.contains(domain) && cookie.isSecure && pathMatches
                && (cookie.expiresDate.map { $0 > now } ?? true)
                && connection.authentication.cookieNames.contains { cookie.name == $0 || cookie.name.hasPrefix($0 + ".") }
        }
        return try connection.normalizedCredential(selected.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
    }
}
