import SwiftUI

/// Setup uses catalog metadata only. Connection verification stays in Settings.
struct FirstRunView: View {
    let preferences: ProviderPreferences
    let finish: () -> Void
    let connect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var selected: Set<ProviderID> = []
    @State private var installed: Set<ProviderID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to UsageNow").font(.largeTitle.bold())
            Text("Your AI usage, at a glance.").font(.title3).foregroundStyle(.secondary)
            if step == 0 {
                Label("Find UsageNow in the menu bar", systemImage: "menubar.rectangle")
                Text("See your remaining limits and reset times, and add a widget to your desktop.")
                Text("Local tools provide activity on this Mac. Optional connections add the usage your provider reports.")
                Text("You choose which providers to enable. Connect accounts later in Settings › Providers.")
            } else {
                Text("Choose your providers").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ProviderCatalog.available) { definition in
                            Toggle(isOn: Binding(get: { selected.contains(definition.id) }, set: {
                                if $0 { selected.insert(definition.id) } else { selected.remove(definition.id) }
                            })) {
                                HStack {
                                    Text(verbatim: definition.displayName)
                                    Spacer()
                                    Text(installed.contains(definition.id) ? "Installed" : definition.apiKey == nil ? "Local source" : "Connect in Settings")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(.trailing, 8)
                }.frame(height: 230)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Skip Setup") { finish(); dismiss() }
                Spacer()
                if step == 0 {
                    Button("Continue") { step = 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Connect Accounts…") { save(); connect(); dismiss() }
                    Button("Done") { save(); dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28).frame(width: 510, height: 480)
        .onAppear {
            selected = preferences.enabledProviders
            installed = LocalToolDiscovery.installed()
        }
        // Closing the window is an explicit skip, including the first launch.
        .onDisappear { finish() }
    }

    private func save() {
        for definition in ProviderCatalog.available {
            // Enabling a connection without a saved credential is safe: it
            // remains disconnected until verified by the existing Settings UI.
            preferences.setEnabled(selected.contains(definition.id), for: definition.id)
        }
        finish()
    }
}
