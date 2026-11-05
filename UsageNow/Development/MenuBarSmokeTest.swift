#if DEBUG
import AppKit

/// Exercises the real menu bar scenes with fixtures, isolated preferences, and
/// no live providers, updates, telemetry, credentials, or widget publication.
/// Run through scripts/test-menubar-runtime.py, which supplies a watchdog even
/// when a SwiftUI render loop prevents the main actor from making progress.
@MainActor
enum MenuBarSmokeTest {
    static var isEnabled: Bool { CommandLine.arguments.contains("--menubar-smoke-test") || isPreview }
    private static var isPreview: Bool { CommandLine.arguments.contains("--menubar-preview") }

    static func makeState() -> AppState {
        let suite = "com.usagenow.MenuBarSmokeTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let fixtures: [any UsageProvider] = isPreview ? [
            PreviewProvider(id: .codex, remaining: 58), PreviewProvider(id: .claudeCode, remaining: 72),
            PreviewProvider(id: .antigravity, remaining: 70), PreviewProvider(id: .cursor, remaining: 83),
            PreviewProvider(id: .windsurf, remaining: 81), PreviewProvider(id: .copilot, remaining: 46),
        ] : [MockCodexProvider(), MockClaudeProvider(), MockGeminiProvider(), MockAntigravityProvider()]
        let state = AppState(providers: fixtures, defaults: defaults,
            widgetSnapshots: WidgetSnapshotWriter(store: nil))
        state.firstRun.complete()
        if CommandLine.arguments.contains("--start-with-provider-icons") {
            state.preferences.menuBarItems = .init(layout: .providers, sources: [SourceKey(provider: .codex)])
        }
        state.startMenuBarClock()
        Task {
            if isPreview { await preview(state, defaults: defaults, suite: suite) }
            else { await run(state, defaults: defaults, suite: suite) }
        }
        return state
    }

    private struct PreviewProvider: UsageProvider {
        let id: ProviderID
        let remaining: Double
        func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
            let now = Date.now
            return ProviderSnapshot(provider: id, status: .available,
                windows: [UsageWindow(kind: .fiveHour, usage: UsagePercentage(percent: 100 - remaining),
                    resetsAt: now.addingTimeInterval(7200))], updatedAt: now)
        }
    }

    private static func preview(_ state: AppState, defaults: UserDefaults, suite: String) async {
        let ids: [ProviderID] = CommandLine.arguments.contains("--preview-second-set")
            ? [.codex, .claudeCode, .windsurf, .copilot] : [.codex, .claudeCode, .antigravity, .cursor]
        await state.store.setEnabledProviders(Set(ids))
        state.preferences.menuBarItems = .init(layout: .providers, sources: ids.map { SourceKey(provider: $0) })
        await state.store.refresh()
        report("preview: \(ids.map(\.rawValue).joined(separator: ", ")) — synthetic percentages")
        try? await Task.sleep(for: .seconds(180))
        defaults.removePersistentDomain(forName: suite)
        NSApplication.shared.terminate(nil)
    }

    private static func report(_ event: String) {
        print("MENUBAR_SMOKE \(event)")
        fflush(stdout)
    }

    private static func pause() async throws { try await Task.sleep(for: .milliseconds(350)) }

    private static func run(_ state: AppState, defaults: UserDefaults, suite: String) async {
        let heartbeat = Task {
            while !Task.isCancelled {
                report("heartbeat")
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
        defer {
            heartbeat.cancel()
            defaults.removePersistentDomain(forName: suite)
        }
        do {
            let ids: [ProviderID] = [.codex, .claudeCode, .gemini, .antigravity]
            let sources = ids.map { SourceKey(provider: $0) }
            await state.store.setEnabledProviders(Set(ids))
            await state.store.refresh()
            try await pause()
            report("single-provider")
            state.preferences.menuBarItems = .init(layout: .providers, sources: [sources[0]])
            try await pause()
            for iteration in 0..<8 {
                report("four-providers-\(iteration)")
                state.preferences.menuBarItems = .init(layout: .providers, sources: sources)
                try await pause()
                state.preferences.menuBarItems.move(sources[3], by: -3)
                try await pause()
                state.accountSets.selectedID = "work" // Empty set: original icon fallback.
                try await pause()
                state.accountSets.selectedID = AccountSets.allID
                try await pause()
                await state.store.setEnabledProviders([])
                try await pause()
                await state.store.setEnabledProviders(Set(ids))
                try await pause()
                state.preferences.menuBarItems.layout = .usageNow
                try await pause()
                guard state.preferences.menuBarItems.sources.count == 4 else {
                    report("failed: switching modes lost selected accounts")
                    NSApplication.shared.terminate(nil)
                    return
                }
            }
            state.preferences.menuBarItems.layout = .providers
            report("waiting-for-clock")
            let beforeTick = state.menuBarClock.now
            try await Task.sleep(for: .seconds(16))
            guard state.menuBarClock.now > beforeTick else {
                report("failed: provider icon clock did not advance")
                NSApplication.shared.terminate(nil)
                return
            }
            report("passed")
            NSApplication.shared.terminate(nil)
        } catch {
            report("failed: \(error)")
            NSApplication.shared.terminate(nil)
        }
    }
}
#endif
