import Foundation

/// Another account of a provider, added in Settings › Providers beside the
/// one UsageNow finds on its own.
///
/// A local tool's account is a second folder of its own — Codex with
/// `CODEX_HOME`, Claude Code with `CLAUDE_CONFIG_DIR` pointing at it. An API
/// provider's account is another key, kept in the Keychain like the first.
/// The name is the person's own label, such as "Work"; UsageNow never reads
/// an account's name or email from the tool.
struct ProviderAccount: Codable, Hashable, Sendable, Identifiable {
    /// Local and random. Names the Keychain item of an API account's key.
    let id: String
    let provider: ProviderID
    var name: String
    /// The tool's folder, for a local tool. `nil` for an API account.
    var folder: String?

    init(id: String = UUID().uuidString, provider: ProviderID, name: String, folder: String? = nil) {
        self.id = id
        self.provider = provider
        self.name = name
        self.folder = folder
    }

    var tag: AccountTag { AccountTag(id: id, name: name) }

    var folderURL: URL? { folder.map { URL(filePath: $0, directoryHint: .isDirectory) } }

    /// How a provider tells its accounts apart, if it can have more than one.
    enum Kind: Sendable, Equatable {
        /// A folder the tool is pointed at with an environment variable.
        case folder(variable: String, defaultPath: String)
        case apiKey
    }

    static func kind(for provider: ProviderID) -> Kind? {
        switch provider {
        case .codex: .folder(variable: "CODEX_HOME", defaultPath: "~/.codex")
        case .claudeCode: .folder(variable: "CLAUDE_CONFIG_DIR", defaultPath: "~/.claude")
        default: ProviderCatalog.definition(for: provider).apiKey != nil ? .apiKey : nil
        }
    }

    static func supportsAccounts(_ provider: ProviderID) -> Bool {
        kind(for: provider) != nil
    }
}

/// Which added account a reading belongs to, for display.
struct AccountTag: Codable, Hashable, Sendable {
    let id: String
    var name: String
}

/// One row's identity: a provider's own account (`account == nil`) or an
/// added one.
struct SourceKey: Hashable, Sendable, CustomStringConvertible {
    let provider: ProviderID
    var account: String? = nil

    var description: String { account.map { "\(provider.rawValue)@\($0)" } ?? provider.rawValue }
}

extension ProviderID {
    /// "Codex", or "Codex · Work" for an added account.
    func displayName(account: AccountTag?) -> String {
        account.map { "\(displayName) · \($0.name)" } ?? displayName
    }
}
