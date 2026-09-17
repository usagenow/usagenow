import SwiftUI

/// Which providers UsageNow tracks, plus the roadmap.
///
/// Roadmap rows are labels only: no toggles, no "Connect", and nothing
/// behind them — those providers have no integration yet.
struct ProvidersSettingsView: View {
    @Bindable var preferences: ProviderPreferences
    /// Reads whether a key is saved; the key itself never reaches this view.
    var hasAPIKey: (ProviderID) -> Bool = { _ in false }
    /// Saves a key, or removes it when `nil`.
    var setAPIKey: (String?, ProviderID) throws -> Void = { _, _ in }

    @State private var editingKeyFor: ProviderDefinition?
    /// Bumped after a save or removal, so key status is read again.
    @State private var keyRevision = 0

    var body: some View {
        Form {
            Section {
                Text("Choose which services UsageNow displays and monitors, and drag them into the order you want.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(preferences.order, id: \.self) { id in
                    availableRow(ProviderCatalog.definition(for: id))
                }
            } header: {
                Text("Available")
            }

            Section {
                ForEach(ProviderCatalog.comingSoon) { definition in
                    HStack(spacing: 8) {
                        ProviderRowLabel(definition: definition)
                        Spacer(minLength: 8)
                        Text("Coming soon")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.badgeFill, in: .capsule)
                    }
                    .opacity(0.6)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Coming soon")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $editingKeyFor) { definition in
            APIKeySheet(definition: definition) { key in
                try setAPIKey(key, definition.id)
                keyRevision += 1
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
        let saved = { _ = keyRevision; return hasAPIKey(definition.id) }()
        HStack(spacing: 8) {
            Label(saved ? "API key saved" : "No API key yet", systemImage: saved ? "key.fill" : "key")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if saved {
                Button("Replace…") { editingKeyFor = definition }
                Button("Remove") {
                    try? setAPIKey(nil, definition.id)
                    keyRevision += 1
                }
            } else {
                Button("Add API Key…") { editingKeyFor = definition }
            }
        }
        .controlSize(.small)
        .padding(.leading, 60)
    }
}

/// Asks for a provider's API key and says plainly what happens to it.
private struct APIKeySheet: View {
    let definition: ProviderDefinition
    let save: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderLogoTile(provider: definition.id)
                Text("\(definition.displayName) API key")
                    .font(.headline)
            }

            SecureField("API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            VStack(alignment: .leading, spacing: 6) {
                if let host = definition.apiKey?.host {
                    Text("UsageNow uses this key only to read your usage from \(host). It stays in the Keychain on this Mac, is never sent anywhere else, and is deleted when you turn \(definition.displayName) off.")
                }
                Text("API keys can usually spend money, not just read it. If \(definition.displayName) lets you, create a separate key for UsageNow.")
                    .foregroundStyle(.orange)
                if let page = definition.apiKey?.keysPage {
                    Link("Create a key on \(definition.displayName)…", destination: page)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if failed {
                Text("The key couldn’t be saved to the Keychain.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func submit() {
        do {
            try save(key)
            key = ""
            dismiss()
        } catch {
            failed = true
        }
    }
}

private struct ProviderRowLabel: View {
    let definition: ProviderDefinition

    var body: some View {
        HStack(spacing: 8) {
            ProviderLogoTile(provider: definition.id)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: definition.displayName)
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
