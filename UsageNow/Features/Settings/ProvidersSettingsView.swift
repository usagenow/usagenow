import SwiftUI

/// Which providers UsageNow tracks, plus the roadmap.
///
/// Roadmap rows are labels only: no toggles, no "Connect", and nothing
/// behind them — those providers have no integration yet.
struct ProvidersSettingsView: View {
    @Bindable var preferences: ProviderPreferences
    var accountSets: AccountSets? = nil
    var accountStates: [ProviderState] = []
    /// Reads whether a key is saved — the first account's (`nil`) or an
    /// added one's; the key itself never reaches this view.
    var hasAPIKey: (ProviderID, String?) -> Bool = { _, _ in false }
    /// Saves a key, or removes it when `nil`.
    var setAPIKey: (String?, ProviderID, String?) throws -> Void = { _, _, _ in }
    /// Removes an added account and its key.
    var removeAccount: (ProviderAccount) -> Void = { _ in }

    /// Whose key the key sheet edits.
    private struct KeyTarget: Identifiable {
        let definition: ProviderDefinition
        var account: ProviderAccount?

        var id: String { account?.id ?? definition.id.rawValue }
    }

    @State private var editingKey: KeyTarget?
    @State private var addingAccountFor: ProviderDefinition?
    @State private var renamingAccount: ProviderAccount?

    /// Tall enough for most of the list, short enough for a 13-inch screen
    /// with room for the window's title and tabs.
    static var height: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return min(640, max(380, screen - 200))
    }
    /// Bumped after a save or removal, so key status is read again.
    @State private var keyRevision = 0
    @State private var showsAccountSets = false

    var body: some View {
        Form {
            Section {
                Text("Choose which services UsageNow displays and monitors, and drag them into the order you want.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let accountSets {
                    HStack {
                        Text("Account sets")
                        Spacer()
                        AccountSetsPicker(sets: accountSets)
                        Button("Manage…") { showsAccountSets = true }
                    }
                }
            }

            Section {
                ForEach(preferences.order, id: \.self) { id in
                    availableRow(ProviderCatalog.definition(for: id))
                }
            } header: {
                Text("Available")
            }

            if !ProviderCatalog.comingSoon.isEmpty {
                Section {
                    // One row: they're labels only, and a row each made the
                    // list taller than a laptop screen.
                    HStack(spacing: 8) {
                        HStack(spacing: -4) {
                            ForEach(ProviderCatalog.comingSoon) { definition in
                                ProviderLogoTile(provider: definition.id)
                            }
                        }
                        Text(verbatim: ProviderCatalog.comingSoon.map(\.displayName).formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("Coming soon")
                }
            }
        }
        .formStyle(.grouped)
        // The list outgrew a laptop screen, so this tab scrolls within a
        // height that fits, unlike the others, which size to their content.
        .frame(height: Self.height)
        .sheet(isPresented: $showsAccountSets) {
            if let accountSets { AccountSetsSettingsView(sets: accountSets, states: accountStates) }
        }
        .sheet(item: $editingKey) { target in
            APIKeySheet(definition: target.definition, account: target.account) { key in
                try setAPIKey(key, target.definition.id, target.account?.id)
                keyRevision += 1
            }
        }
        .sheet(item: $renamingAccount) { account in
            RenameAccountSheet(
                account: account,
                otherNames: preferences.accounts(for: account.provider).filter { $0.id != account.id }.map(\.name)
            ) { name in
                preferences.renameAccount(id: account.id, to: name)
            }
        }
        .sheet(item: $addingAccountFor) { definition in
            if let kind = ProviderAccount.kind(for: definition.id) {
                AddAccountSheet(
                    definition: definition,
                    kind: kind,
                    existingNames: preferences.accounts(for: definition.id).map(\.name)
                ) { account, key in
                    // The key first, so the account's first reading finds it.
                    if let key { try setAPIKey(key, definition.id, account.id) }
                    preferences.addAccount(account)
                    keyRevision += 1
                }
            }
        }
    }

    /// A toggle row that can be dragged onto another to take its place.
    /// The context menu offers the same moves without a pointer.
    private func availableRow(_ definition: ProviderDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Toggle(isOn: preferences.binding(for: definition.id)) {
                    ProviderRowLabel(definition: definition)
                }
            }
            if definition.apiKey != nil, preferences.isEnabled(definition.id) {
                apiKeyStatus(definition)
            }
            if let kind = ProviderAccount.kind(for: definition.id), preferences.isEnabled(definition.id) {
                ProviderAccountsView(
                    definition: definition,
                    kind: kind,
                    accounts: preferences.accounts(for: definition.id),
                    hasKey: { hasAPIKey($0.provider, $0.id) },
                    keyRevision: keyRevision,
                    onAdd: { addingAccountFor = definition },
                    onReplaceKey: { editingKey = KeyTarget(definition: definition, account: $0) },
                    onRename: { renamingAccount = $0 },
                    onRemove: { account in
                        withAnimation(.snappy) { removeAccount(account) }
                        keyRevision += 1
                    }
                )
            }
        }
        .contentShape(.rect)
        .draggable(definition.id.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first.flatMap(ProviderID.init(rawValue:)) else { return false }
            withAnimation(.snappy) { preferences.move(moved, to: definition.id) }
            return true
        }
        .contextMenu {
            Button("Move Up") { withAnimation(.snappy) { preferences.move(definition.id, by: -1) } }
                .disabled(preferences.order.first == definition.id)
            Button("Move Down") { withAnimation(.snappy) { preferences.move(definition.id, by: 1) } }
                .disabled(preferences.order.last == definition.id)
        }
        .accessibilityAction(named: Text("Move Up")) { preferences.move(definition.id, by: -1) }
        .accessibilityAction(named: Text("Move Down")) { preferences.move(definition.id, by: 1) }
    }
}

extension ProvidersSettingsView {
    /// "API key saved" with Replace and Remove, or a button to add one.
    @ViewBuilder
    private func apiKeyStatus(_ definition: ProviderDefinition) -> some View {
        let saved = { _ = keyRevision; return hasAPIKey(definition.id, nil) }()
        HStack(spacing: 8) {
            Label { Text(definition.apiKey?.statusTitle(saved: saved) ?? "Not connected") } icon: {
                Image(systemName: saved ? "key.fill" : "key")
            }
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if saved {
                Button("Replace…") { editingKey = KeyTarget(definition: definition) }
                Button("Remove") {
                    try? setAPIKey(nil, definition.id, nil)
                    keyRevision += 1
                }
            } else {
                Button("Connect…") { editingKey = KeyTarget(definition: definition) }
            }
        }
        .controlSize(.small)
        .padding(.leading, 60)
    }
}

/// Asks for a provider's API key and says plainly what happens to it.
struct APIKeySheet: View {
    let definition: ProviderDefinition
    var account: ProviderAccount?
    let save: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var verification = ConnectionVerification()
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderLogoTile(provider: definition.id)
                Text("Connect \(definition.id.displayName(account: account?.tag))")
                    .font(.headline)
            }

            ConnectionCredentialField(definition: definition, credential: $key)
                .disabled(checkTask != nil)

            APIKeyNotes(definition: definition)

            ConnectionCheckFeedback(verification: verification)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Check and Save", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checkTask != nil || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onDisappear(perform: cancel)
    }

    private func submit() {
        guard checkTask == nil else { return }
        let credential = key
        checkTask = Task { @MainActor in
            defer { checkTask = nil }
            if await verification.checkAndSave(credential, for: definition.id, save: save) {
                key = ""
                dismiss()
            }
        }
    }

    private func cancel() { checkTask?.cancel(); verification.cancel(); key = "" }
}

private struct ProviderRowLabel: View {
    let definition: ProviderDefinition

    var body: some View {
        HStack(spacing: 8) {
            ProviderLogoTile(provider: definition.id)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: definition.displayName)
                    if definition.isExperimental {
                        Text("Experimental")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Palette.badgeFill, in: .capsule)
                    }
                }
                if let summary = definition.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Providers") {
    ProvidersSettingsView(preferences: ProviderPreferences(defaults: UserDefaults(suiteName: "preview")!))
        .frame(width: SettingsView.width)
}
#endif
