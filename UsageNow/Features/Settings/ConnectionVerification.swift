import Foundation
import Observation
import SwiftUI

/// Shared by the first-account and extra-account sheets. Cancellation or
/// a late response can never overwrite the connection that was there before.
@MainActor
@Observable
final class ConnectionVerification {
    private(set) var isChecking = false
    private(set) var failure: ConnectionCheckFailure?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let verify: @Sendable (String, ProviderID) async throws -> String

    init(verify: @escaping @Sendable (String, ProviderID) async throws -> String = {
        try await ProviderConnectionVerifier().verify($0, for: $1)
    }) { self.verify = verify }

    func checkAndSave(_ credential: String, for provider: ProviderID,
                      save: (String) throws -> Void) async -> Bool {
        guard !isChecking else { return false }
        let attempt = UUID()
        generation = attempt
        isChecking = true
        failure = nil
        defer { if generation == attempt { isChecking = false } }
        do {
            try Task.checkCancellation()
            let verified = try await verify(credential, provider)
            try Task.checkCancellation()
            guard generation == attempt else { return false }
            do {
                try save(verified)
                return true
            } catch {
                failure = .storage
            }
        } catch is CancellationError {
            // Closing the sheet is not an error and must not save anything.
        } catch {
            guard generation == attempt, !Task.isCancelled else { return false }
            failure = ConnectionCheckFailure(error)
        }
        return false
    }

    func cancel() {
        generation = UUID()
        isChecking = false
        failure = nil
    }
}

enum ConnectionCheckFailure: Equatable {
    case format, rejected, permission, offline, unavailable, unsupported, storage
    case rateLimited(Date)

    init(_ error: any Error) {
        switch error {
        case APIKeyClient.Failure.invalidCredential: self = .format
        case APIKeyClient.Failure.rejectedKey: self = .rejected
        case APIKeyClient.Failure.permissionDenied: self = .permission
        case APIKeyClient.Failure.unreadableResponse: self = .unsupported
        case APIKeyClient.Failure.rateLimited(let date): self = .rateLimited(date)
        case let error as URLError where [.notConnectedToInternet, .networkConnectionLost].contains(error.code): self = .offline
        default: self = .unavailable
        }
    }

    /// No raw response, URL, credential, or server-provided error text.
    var message: String {
        switch self {
        case .format: String(localized: "Check the credential format. Session cookies must include their name.")
        case .rejected: String(localized: "The service rejected this connection. Check the credential and its permissions, or sign in again.")
        case .permission: String(localized: "This key cannot read usage. Enable the required read permission and try again.")
        case .offline: String(localized: "No internet connection. Reconnect and try again; nothing has been saved.")
        case .unavailable: String(localized: "The service couldn’t be reached. Try again later; nothing has been saved.")
        case .unsupported: String(localized: "Signed-in usage couldn’t be verified. This account or response may not be supported; nothing has been saved.")
        case .storage: String(localized: "Connection verified, but it couldn’t be saved. Check Keychain access and try again.")
        case .rateLimited(let date): RateLimitMessage.until(date)
        }
    }
}

enum RateLimitMessage {
    static func until(_ date: Date) -> String {
        let time = date.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Refresh temporarily limited. Try again after \(time).")
    }
}

struct ConnectionCheckFeedback: View {
    let verification: ConnectionVerification
    var body: some View {
        if verification.isChecking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking connection…").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        if let failure = verification.failure {
            Text(failure.message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
