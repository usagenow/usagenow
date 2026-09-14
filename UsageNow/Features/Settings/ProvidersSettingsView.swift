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
    }

    /// A toggle row that can be dragged onto another to take its place.
    /// The context menu offers the same moves without a pointer.
    private func availableRow(_ definition: ProviderDefinition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Toggle(isOn: preferences.binding(for: definition.id)) {
                ProviderRowLabel(definition: definition)
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
