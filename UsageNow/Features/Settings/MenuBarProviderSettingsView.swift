import SwiftUI

/// These are existing enabled accounts, never connection switches. Changing
/// the menu bar cannot enable a provider or read any additional credentials.
struct MenuBarProviderSettingsView: View {
    @Bindable var preferences: AppPreferences
    let providers: ProviderPreferences
    var store: UsageStore? = nil
    var accountSets: AccountSets? = nil

    private var choices: [SourceKey] {
        let allowed = accountSets?.active.map { Set($0.sources) }
        return providers.order.filter { providers.enabledProviders.contains($0) }.flatMap { provider in
            [SourceKey(provider: provider)] + providers.accounts(for: provider).map { SourceKey(provider: provider, account: $0.id) }
        }.filter { allowed?.contains($0) ?? true }
    }

    private var layout: Binding<MenuBarLayout> {
        Binding(get: { preferences.menuBarItems.layout }, set: { value in
            var items = preferences.menuBarItems
            if value == .providers, items.sources.isEmpty {
                // Prefer tools already present on this Mac for the initial
                // choice. An explicitly cleared selection remains empty.
                let detected = choices.filter { key in store?.states.contains { $0.id == key && $0.isVisible } ?? false }
                items = MenuBarItemsConfiguration(layout: value, sources: Array((detected.isEmpty ? choices : detected).prefix(2)))
            }
            items.layout = value
            preferences.menuBarItems = items
        })
    }

    var body: some View {
        Section {
            Picker("Menu bar icons", selection: layout) {
                Text("UsageNow icon").tag(MenuBarLayout.usageNow)
                Text("Provider icons").tag(MenuBarLayout.providers)
            }
            .pickerStyle(.segmented)
        } footer: {
            if preferences.menuBarItems.layout == .providers {
                Text("Choose up to four accounts. Each icon shows its most critical limit.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }

        if preferences.menuBarItems.layout == .providers {
            Section("Selected accounts") {
                ForEach(preferences.menuBarItems.sources, id: \.self) { source in
                    HStack(spacing: 8) {
                        ProviderLogo(provider: source.provider).frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(verbatim: title(source)).lineLimit(2)
                            .foregroundStyle(choices.contains(source) ? .primary : .secondary)
                        Spacer(minLength: 4)
                        Button { preferences.menuBarItems.move(source, by: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(preferences.menuBarItems.sources.first == source)
                            .help("Move Up").accessibilityLabel(Text("Move Up"))
                        Button { preferences.menuBarItems.move(source, by: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(preferences.menuBarItems.sources.last == source)
                            .help("Move Down").accessibilityLabel(Text("Move Down"))
                        Button { preferences.menuBarItems.select(source, included: false) } label: { Image(systemName: "minus.circle") }
                            .help("Remove").accessibilityLabel(Text("Remove"))
                    }
                    .buttonStyle(.borderless)
                }
                if let store, preferences.menuBarItems.visibleSources(in: store.states,
                    enabled: store.enabledProviders, set: accountSets?.active).isEmpty {
                    Text("No selected accounts are available in this set. The UsageNow icon stays visible.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Accounts") {
                ForEach(choices, id: \.self) { source in
                    Toggle(isOn: Binding(get: { preferences.menuBarItems.sources.contains(source) }, set: { included in
                        preferences.menuBarItems.select(source, included: included)
                    })) {
                        Text(verbatim: title(source))
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!preferences.menuBarItems.sources.contains(source)
                        && preferences.menuBarItems.sources.count >= MenuBarItemsConfiguration.maximumItems)
                }
            }
        }
    }

    private func title(_ source: SourceKey) -> String {
        let account = providers.accounts.first { $0.id == source.account && $0.provider == source.provider }
        return source.provider.displayName(account: account?.tag)
    }
}
