import SwiftUI

/// Which providers UsageNow tracks, plus the roadmap.
///
/// Roadmap rows are labels only: no toggles, no "Connect", and nothing
/// behind them — those providers have no integration yet.
struct ProvidersSettingsView: View {
    @Bindable var preferences: ProviderPreferences

    var body: some View {
        Form {
            Section {
                Text("Choose which services UsageNow displays and monitors.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(ProviderCatalog.available) { definition in
                    Toggle(isOn: preferences.binding(for: definition.id)) {
                        ProviderRowLabel(definition: definition)
                    }
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
