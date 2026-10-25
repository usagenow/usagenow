import SwiftUI

@MainActor
struct CLISettingsView: View {
    @State private var installed = false
    @State private var failed = false
    private var helper: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers/usagenow") }
    private var link: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/usagenow") }
    private var installation: CLIInstallation { CLIInstallation(helper: helper, link: link) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Command line")
                Spacer()
                Button(installed ? "Remove CLI" : "Install CLI") { installOrRemove() }
            }
            Text("Read your latest usage with usagenow status or usagenow status --json.")
                .font(.callout).foregroundStyle(.secondary)
            Text(verbatim: link.path).font(.caption.monospaced()).textSelection(.enabled)
            Text("Add ~/.local/bin to your PATH if needed. Shell settings are never changed automatically.")
                .font(.caption).foregroundStyle(.secondary)
            if failed {
                Text("Couldn’t install the command. Check the folder permissions or an existing usagenow command.")
                    .foregroundStyle(.red).font(.callout)
            }
        }
        .onAppear { installed = installation.isInstalled }
    }

    private func installOrRemove() {
        failed = false
        do {
            if installation.isInstalled {
                try installation.remove()
            } else {
                try installation.install()
            }
            installed = installation.isInstalled
        } catch { failed = true }
    }
}
