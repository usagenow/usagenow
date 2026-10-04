import AppKit

/// Quits UsageNow and opens it again, so a new language takes effect.
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/sh")
        // The path is passed as an argument, never spliced into the script.
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            Log.app.error("Couldn’t schedule the relaunch")
            return
        }
        NSApplication.shared.terminate(nil)
    }
}
