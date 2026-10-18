import Foundation

/// Local AI Assistant quota only. No JetBrains HTTP client, Keychain access,
/// login, account data, conversation parsing, or credential renewal.
struct JetBrainsProvider: UsageProvider {
    let id: ProviderID = .jetbrains
    private let discover: @Sendable () -> JetBrainsEnvironment
    private let read: @Sendable (JetBrainsEnvironment.Installation, Date) -> JetBrainsQuota?
    private let now: @Sendable () -> Date

    init(
        discover: @escaping @Sendable () -> JetBrainsEnvironment = { .discover() },
        read: @escaping @Sendable (JetBrainsEnvironment.Installation, Date) -> JetBrainsQuota? = { JetBrainsQuotaReader.read($0, now: $1) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.discover = discover
        self.read = read
        self.now = now
    }

    func fetchSnapshot(trigger: RefreshTrigger) async throws -> ProviderSnapshot {
        let date = now()
        let discover = discover
        let read = read
        // Bound disk I/O to a utility task, off the UI/cooperative executor.
        return await Task.detached(priority: .utility) {
            guard let installation = discover().selected else { return .notInstalled(.jetbrains, at: date) }
            let quota = read(installation, date)
            let windows = quota?.windows(at: date) ?? []
            return ProviderSnapshot(
                provider: .jetbrains, status: .available,
                windows: windows,
                quotaUnavailableReason: windows.contains { $0.usage != nil } ? nil : .toolNotRunning,
                updatedAt: date, limitsUpdatedAt: quota?.observedAt,
                sourceLabel: installation.name
            )
        }.value
    }
}
