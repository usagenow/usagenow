import AppKit
import SwiftUI

/// A provider's added accounts under its row in Settings › Providers, and
/// the button to add one.
struct ProviderAccountsView: View {
    let definition: ProviderDefinition
    let kind: ProviderAccount.Kind
    let accounts: [ProviderAccount]
    /// Whether an added account has a key; read again after `keyRevision` changes.
    let hasKey: (ProviderAccount) -> Bool
    let keyRevision: Int
    let onAdd: () -> Void
    let onReplaceKey: (ProviderAccount) -> Void
    let onRename: (ProviderAccount) -> Void
    let onRemove: (ProviderAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(accounts) { account in
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: account.name)
                        Text(detail(for: account))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isFolderMissing(account) {
                            Text("Folder not found")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    // One menu, so the row fits in every language.
                    Menu {
                        Button("Rename…") { onRename(account) }
                        if kind == .apiKey {
                            Button("Reconnect…") { onReplaceKey(account) }
                        }
                        Divider()
                        Button("Remove", role: .destructive) { onRemove(account) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(Text("Actions for \(account.name)"))
                }
                .accessibilityElement(children: .contain)
            }
            HStack {
                Button("Add Account…", action: onAdd)
                Spacer(minLength: 0)
            }
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.leading, 60)
    }

    /// The folder was moved or deleted since it was chosen.
    private func isFolderMissing(_ account: ProviderAccount) -> Bool {
        guard kind != .apiKey, let folder = account.folder else { return false }
        var isDirectory: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    private func detail(for account: ProviderAccount) -> String {
        switch kind {
        case .folder:
            return account.folder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
        case .apiKey:
            _ = keyRevision
            return String(localized: definition.apiKey?.statusTitle(saved: hasKey(account)) ?? "Not connected")
        }
    }
}

/// Names a new account and points it at its folder or key.
struct AddAccountSheet: View {
    let definition: ProviderDefinition
    let kind: ProviderAccount.Kind
    /// Names already used for this provider, so two rows can't look alike.
    let existingNames: [String]
    /// Saves the account, with its key for an API account.
    let save: (ProviderAccount, String?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var folder: URL?
    @State private var key = ""
    @State private var failed = false
    @State private var verification = ConnectionVerification()
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderLogoTile(provider: definition.id)
                Text("Add \(definition.displayName) Account")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $name, prompt: Text("Work"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(checkTask != nil)
                if isNameTaken {
                    Text("Another \(definition.displayName) account already has this name.")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("Shown after \(definition.displayName) in the menu bar window and the widget. UsageNow never reads the account’s own name or email.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch kind {
            case .folder(let variable, let defaultPath):
                folderPicker(variable: variable, defaultPath: defaultPath)
            case .apiKey:
                ConnectionCredentialField(definition: definition, credential: $key)
                    .disabled(checkTask != nil)
                APIKeyNotes(definition: definition)
                ConnectionCheckFeedback(verification: verification)
            }

            if failed {
                Text("Couldn’t save the connection. Check the credential format and Keychain access.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    if kind == .apiKey { Text("Check and Add Account") }
                    else { Text("Add Account") }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || checkTask != nil)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onDisappear(perform: cancel)
    }

    @ViewBuilder
    private func folderPicker(variable: String, defaultPath: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        if folder == nil {
                            Text("No folder chosen").foregroundStyle(.secondary)
                        }
                    }
                Button("Choose…", action: chooseFolder)
            }
            if isDefaultFolder(defaultPath) {
                Text("UsageNow already reads this folder as the first \(definition.displayName) account.")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                Text("The folder \(definition.displayName) uses when \(variable) is set to it. Only usage is read from it, as from \(defaultPath).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isNameTaken: Bool {
        existingNames.contains { $0.compare(trimmedName, options: .caseInsensitive) == .orderedSame }
    }

    private func isDefaultFolder(_ defaultPath: String) -> Bool {
        guard let folder else { return false }
        let standard = URL(filePath: (defaultPath as NSString).expandingTildeInPath).standardizedFileURL.path
        return folder.standardizedFileURL.path == standard
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty, !isNameTaken else { return false }
        switch kind {
        case .folder(_, let defaultPath): return folder != nil && !isDefaultFolder(defaultPath)
        case .apiKey: return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // The tools' folders start with a dot.
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
        }
    }

    private func submit() {
        guard canSave, checkTask == nil else { return }
        let account = ProviderAccount(provider: definition.id, name: trimmedName, folder: folder?.path)
        if kind == .apiKey {
            let credential = key
            checkTask = Task { @MainActor in
                defer { checkTask = nil }
                if await verification.checkAndSave(credential, for: definition.id, save: { try save(account, $0) }) {
                    key = ""
                    dismiss()
                }
            }
            return
        }
        do {
            try save(account, nil)
            dismiss()
        } catch {
            failed = true
        }
    }

    private func cancel() { checkTask?.cancel(); verification.cancel(); key = "" }
}

/// What happens to an API key, said wherever one is asked for.
struct APIKeyNotes: View {
    let definition: ProviderDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let connection = definition.apiKey {
                Text("UsageNow sends this credential only to \(connection.host) to read usage. It is stored in Keychain on this Mac and deleted when you turn \(definition.displayName) off.")
                if connection.authentication.isSession {
                    Text("A session cookie grants access to your web account. UsageNow never imports existing browser profiles or renews the session. Sign in again when it expires.")
                        .foregroundStyle(.orange)
                } else if connection.authentication == .githubToken {
                    Text("Use your own GitHub token. Copilot access depends on the token and account; the experimental API may reject personal tokens. UsageNow does not sign in as VS Code.")
                } else if connection.authentication == .elevenLabs {
                    Text("Create a restricted key with user_read permission. UsageNow does not generate audio.")
                } else {
                    Text("API keys can usually spend money, not just read it. If \(definition.displayName) lets you, create a separate key for UsageNow.")
                        .foregroundStyle(.orange)
                }
            }
            if definition.isExperimental {
                Text("Experimental: \(definition.displayName) doesn’t document how to read usage, so this may stop working without notice. If it does, UsageNow shows limits as unavailable rather than guessing.")
            }
            if let page = definition.apiKey?.keysPage {
                Link("Open \(definition.displayName)…", destination: page)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Gives an added account a new name.
struct RenameAccountSheet: View {
    let account: ProviderAccount
    /// Names the provider's other accounts use.
    let otherNames: [String]
    let rename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(account: ProviderAccount, otherNames: [String], rename: @escaping (String) -> Void) {
        self.account = account
        self.otherNames = otherNames
        self.rename = rename
        _name = State(initialValue: account.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderLogoTile(provider: account.provider)
                Text("Rename \(account.provider.displayName(account: account.tag))")
                    .font(.headline)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                if isNameTaken {
                    Text("Another \(account.provider.displayName) account already has this name.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isNameTaken: Bool {
        otherNames.contains { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    private var canSave: Bool { !trimmed.isEmpty && !isNameTaken }

    private func submit() {
        guard canSave else { return }
        rename(trimmed)
        dismiss()
    }
}
