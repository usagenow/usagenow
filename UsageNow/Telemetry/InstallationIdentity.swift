import Foundation
import Synchronization

/// A random identifier for this installation, used only for anonymous
/// analytics.
///
/// It's a locally generated UUID — not derived from hardware identifiers,
/// serial or MAC addresses, the Apple ID, user name, or host name. It's
/// created the first time analytics actually sends something, stored in the
/// keychain so it survives app updates, and replaced when analytics state
/// is reset. It isn't shown in the UI.
final class InstallationIdentity: Sendable {
    static let storageKey = "installation-id"

    private let store: any SecureStore
    private let cached = Mutex<UUID?>(nil)

    init(store: any SecureStore = KeychainStore()) {
        self.store = store
    }

    /// The identifier, generating and storing one if none exists.
    func identifier() throws -> UUID {
        try cached.withLock { cached in
            if let cached { return cached }
            if let stored = try storedIdentifier() {
                cached = stored
                return stored
            }
            let new = UUID()
            try store.setData(Data(new.uuidString.utf8), for: Self.storageKey)
            cached = new
            return new
        }
    }

    /// The stored identifier, without creating one.
    func existingIdentifier() -> UUID? {
        cached.withLock { cached in
            cached ?? (try? storedIdentifier())
        }
    }

    /// Deletes the identifier; the next report gets a new one.
    func reset() throws {
        try cached.withLock { cached in
            cached = nil
            try store.removeData(for: Self.storageKey)
        }
    }

    private func storedIdentifier() throws -> UUID? {
        try store.data(for: Self.storageKey)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(UUID.init(uuidString:))
    }
}
