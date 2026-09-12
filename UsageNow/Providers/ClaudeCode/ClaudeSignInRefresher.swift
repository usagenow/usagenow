import Foundation
import Synchronization

/// Asks the installed Claude Code CLI to refresh its own sign-in.
///
/// UsageNow never refreshes, rotates, or writes Claude Code credentials
/// itself — it doesn't even read the refresh token. When the saved access
/// token has expired, it runs the official CLI's cheapest read-only
/// command (`auth status`), which renews the credential the same way it
/// would during normal use, and then re-reads the keychain. This is the
/// same delegation used for Codex, where `codex app-server` authenticates
/// itself.
///
/// It never sends a prompt and never uses `-p`, so no model runs and no
/// quota is consumed. Output is discarded rather than parsed or logged.
struct ClaudeSignInRefresher: Sendable {
    /// Don't ask more often than this, even across failures.
    static let minimumInterval: TimeInterval = 10 * 60
    static let timeout: Duration = .seconds(20)

    var executable: URL
    var timeout: Duration = ClaudeSignInRefresher.timeout

    /// Runs the CLI and reports whether it finished cleanly.
    func requestRefresh() async -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["auth", "status"]
        var environment = ProcessInfo.processInfo.environment
        // These would send the CLI somewhere other than the user's own account.
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY"] {
            environment.removeValue(forKey: key)
        }
        // The CLI finds its keychain item by user name, and an app launched
        // from Finder inherits a sparse environment.
        environment["HOME"] = environment["HOME"] ?? NSHomeDirectory()
        environment["USER"] = environment["USER"] ?? NSUserName()
        environment["LOGNAME"] = environment["LOGNAME"] ?? NSUserName()
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Log.provider.notice("Claude Code CLI couldn’t be started")
            return false
        }

        let running = TerminableProcess(process)
        let watchdog = Task { [timeout] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { running.terminate() }
        }
        defer { watchdog.cancel() }

        await running.waitUntilExit()
        let succeeded = running.terminationStatus == 0
        // Kept at notice level so a failed overnight renewal is still in the log.
        Log.provider.notice("""
            Asked Claude Code (\(executable.lastPathComponent, privacy: .public)) to renew its sign-in: \
            exit \(running.terminationStatus, privacy: .public)
            """)
        return succeeded
    }
}

/// Wraps a `Process` so a watchdog can stop it from another task.
private final class TerminableProcess: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var terminationStatus: Int32 { process.terminationStatus }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func waitUntilExit() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The process can exit before the handler is installed, so resume exactly once.
            let hasResumed = Mutex(false)
            @Sendable func finish() {
                let shouldResume = hasResumed.withLock { resumed in
                    defer { resumed = true }
                    return !resumed
                }
                if shouldResume { continuation.resume() }
            }
            process.terminationHandler = { _ in finish() }
            if !process.isRunning { finish() }
        }
    }
}
