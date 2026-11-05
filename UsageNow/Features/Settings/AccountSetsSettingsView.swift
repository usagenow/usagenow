import SwiftUI

struct AccountSetsPicker: View {
    @Bindable var sets: AccountSets
    var body: some View {
        Picker("Account set", selection: $sets.selectedID) {
            Text("All accounts").tag(AccountSets.allID)
            ForEach(sets.sets) { set in Text(verbatim: set.title).tag(set.id) }
        }
        .labelsHidden()
        .accessibilityLabel(Text("Account set"))
    }
}

struct AccountSetsSettingsView: View {
    @Bindable var sets: AccountSets
    let states: [ProviderState]
    @State private var editingID: String? = "work"
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Account sets").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            Divider()
            HStack(spacing: 0) {
                VStack {
                    List(selection: $editingID) {
                        ForEach(sets.sets) { set in Text(verbatim: set.title).tag(set.id) }
                    }
                    HStack {
                        TextField("New set name", text: $newName)
                            .onSubmit(create)
                        Button(action: create) { Image(systemName: "plus") }
                            .accessibilityLabel(Text("Add account set"))
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(10)
                }.frame(width: 180)
                Divider()
                if let set = sets.sets.first(where: { $0.id == editingID }) {
                    editor(set)
                } else {
                    Text("Choose an account set").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 660, height: 490)
        .onAppear { editingID = sets.active?.id ?? sets.sets.first?.id }
    }

    private func editor(_ set: AccountSet) -> some View {
        Form {
            Section {
                if set.builtIn == nil {
                    TextField("Name", text: Binding(get: { set.name }, set: { name in
                        var changed = set
                        changed.name = String(name.prefix(80))
                        sets.update(changed)
                    }))
                } else { Text(verbatim: set.title).font(.headline) }
                Text("Sets change what you see. Enabled accounts keep updating and sending notifications.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Accounts") {
                ForEach(orderedStates(set)) { state in
                    HStack {
                        Toggle(isOn: Binding(get: { set.sources.contains(state.id) }, set: {
                            sets.setMembership($0, source: state.id, in: set.id)
                        })) { Text(verbatim: state.displayName) }
                        if set.sources.contains(state.id) {
                            Button { sets.move(state.id, by: -1, in: set.id) } label: { Image(systemName: "chevron.up") }
                                .accessibilityLabel(Text("Move Up"))
                                .disabled(set.sources.first == state.id)
                            Button { sets.move(state.id, by: 1, in: set.id) } label: { Image(systemName: "chevron.down") }
                                .accessibilityLabel(Text("Move Down"))
                                .disabled(set.sources.last == state.id)
                        }
                    }.buttonStyle(.borderless)
                }
            }
            Section("Menu Bar") {
                Picker("Display", selection: Binding(get: { set.menuBarSource }, set: { source in
                    var changed = set
                    changed.menuBarSource = source
                    sets.update(changed)
                })) {
                    Text("Most critical usage").tag(nil as SourceKey?)
                    ForEach(orderedStates(set).filter { state in
                        set.sources.contains(state.id) && MenuBarDisplayMode.allCases.contains { $0.requiredProvider == state.provider }
                    }) { state in Text(verbatim: state.displayName).tag(Optional(state.id)) }
                }
            }
            Section {
                Button("Delete account set", role: .destructive) { sets.remove(id: set.id); editingID = sets.sets.first?.id }
            }
        }.formStyle(.grouped)
    }

    private func orderedStates(_ set: AccountSet) -> [ProviderState] {
        let selected = set.sources.compactMap { key in states.first { $0.id == key } }
        return selected + states.filter { !set.sources.contains($0.id) }
    }

    private func create() {
        if let id = sets.create(name: newName) { editingID = id; newName = "" }
    }
}
