import Foundation
import Security

/// Why an experimental quota source is or isn't available, in detail. Kept
/// for logs and diagnosis; the UI shows the shorter `QuotaUnavailableReason`.
enum QuotaSourceAvailability: Sendable, Equatable {
    case available
    /// The experimental setting is off, or the provider isn't tracked.
    case disabled
    /// No saved sign-in, or it expired or was rejected. The provider's own
    /// tool renews it when it runs; UsageNow never does.
    case staleAuthentication
    case keychainDenied
    /// The usage endpoint didn't answer, or answered with an error.
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
struct OAuthAccessToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let value: String
    let expiresAt: Date?

    func isExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }

    // Never reveal the token through string interpolation or debugging output.
    var description: String { "OAuthAccessToken(<redacted>)" }
    var debugDescription: String { description }
}

enum CredentialLookup: Sendable {
    case found(OAuthAccessToken)
    /// No saved sign-in in the keychain.
    case notFound
    /// The user denied access or dismissed a keychain prompt.
    case accessDenied
}

/// Where an experimental quota source gets a provider's existing sign-in.
protocol CredentialSource: Sendable {
    func lookup() async throws -> CredentialLookup
    /// When the saved sign-in last changed, or `nil` when there's none or it
    /// can't be told. Must not read the secret, so it never prompts.
    func lastModified() async -> Date?
}

extension CredentialSource {
    func lastModified() async -> Date? { nil }
}

/// Runs `/usr/bin/security find-generic-password -w` for an item a tool
/// saved through that same command-line tool.
///
/// Such an item trusts `security`, so reading it this way shows no prompt,
/// while the Security framework would ask for the login password after
/// every save the tool makes. The output goes through a pipe straight into
/// memory; nothing is written to disk or logged.
enum SecurityTool {
    static let executable = URL(filePath: "/usr/bin/security")
    /// `security` exits with this when there's no such item.
    static let itemNotFoundStatus: Int32 = 44

    struct Result: Sendable {
        var exitStatus: Int32
        var output: Data
    }

    static func readPassword(service: String, account: String?, timeout: TimeInterval) async -> Result {
        // The tool blocks until it finishes; wait off the concurrency pool.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run(service: service, account: account, timeout: timeout))
            }
        }
    }

    private static func run(service: String, account: String?, timeout: TimeInterval) -> Result {
        let process = Process()
        process.executableURL = executable
        var arguments = ["find-generic-password"]
        if let account { arguments += ["-a", account] }
        arguments += ["-s", service, "-w"]
        process.arguments = arguments
        process.environment = ["HOME": NSHomeDirectory(), "USER": NSUserName()]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Log.provider.notice("Couldn’t run the security tool")
            return Result(exitStatus: itemNotFoundStatus, output: Data())
        }
        let running = TerminableProcess(process)
        let watchdog = DispatchWorkItem { running.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Reading to the end returns when the tool exits and closes the pipe.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return Result(exitStatus: process.terminationStatus, output: data)
    }
}

enum KeychainItem {
    /// When a generic-password item last changed, or `nil` if there's none.
    /// Reads only attributes: the keychain guards an item's data, not its
    /// attributes, so this never shows a prompt.
    static func modificationDate(service: String) -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any] else { return nil }
        return attributes[kSecAttrModificationDate as String] as? Date
    }
}
