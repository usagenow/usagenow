/// A usage window together with the provider it belongs to.
struct ProviderUsageWindow: Sendable, Equatable {
    let provider: ProviderID
    let window: UsageWindow
}

/// Cross-provider views of usage, for the menu bar label and, later,
/// notifications and widgets.
enum UsageSummary {
    /// The window closest to exhaustion across all available providers.
    static func mostCritical(in snapshots: [ProviderSnapshot]) -> ProviderUsageWindow? {
        snapshots
            .compactMap { snapshot in
                snapshot.mostCriticalWindow.map { ProviderUsageWindow(provider: snapshot.provider, window: $0) }
            }
            .max { ($0.window.usage?.value ?? 0) < ($1.window.usage?.value ?? 0) }
    }
}
