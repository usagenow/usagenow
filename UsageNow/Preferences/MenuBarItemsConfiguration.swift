import Foundation

enum MenuBarLayout: String, Codable, CaseIterable, Sendable {
    case usageNow
    case providers
}

/// Display choices only. Every item reads the existing store; adding an icon
/// never starts another provider, refresh timer, or credential lookup.
struct MenuBarItemsConfiguration: Codable, Equatable, Sendable {
    static let maximumItems = 4
    var layout: MenuBarLayout = .usageNow
    private(set) var sources: [SourceKey] = []

    init(layout: MenuBarLayout = .usageNow, sources: [SourceKey] = []) {
        self.layout = layout
        var seen = Set<SourceKey>()
        self.sources = Array(sources.filter { seen.insert($0).inserted }.prefix(Self.maximumItems))
    }

    func validated(against accounts: [ProviderAccount]) -> Self {
        let valid = Set(ProviderCatalog.available.map { SourceKey(provider: $0.id) }
            + accounts.map { SourceKey(provider: $0.provider, account: $0.id) })
        return Self(layout: layout, sources: sources.filter { valid.contains($0) })
    }

    mutating func select(_ source: SourceKey, included: Bool) {
        if included {
            guard sources.count < Self.maximumItems, !sources.contains(source) else { return }
            sources.append(source)
        } else {
            sources.removeAll { $0 == source }
        }
    }

    mutating func move(_ source: SourceKey, by offset: Int) {
        guard let from = sources.firstIndex(of: source) else { return }
        let to = min(max(0, from + offset), sources.count - 1)
        guard to != from else { return }
        sources.remove(at: from)
        sources.insert(source, at: to)
    }

    /// Use stable account identities, including when names or readings change.
    /// Disabled, deleted, and other-set sources cannot occupy a menu bar slot.
    /// A selected tool that isn't installed yields to the UsageNow fallback.
    func visibleSources(in states: [ProviderState], enabled: Set<ProviderID>, set: AccountSet?) -> [SourceKey] {
        guard layout == .providers else { return [] }
        let allowed = set.map { Set($0.sources) }
        return Array(sources.filter { source in
            enabled.contains(source.provider)
                && (allowed?.contains(source) ?? true)
                && states.contains { $0.id == source && $0.snapshot?.status != .notInstalled }
        }.prefix(Self.maximumItems))
    }
}

/// A safe presentation of one source's most critical current window. Unknown
/// usage stays unknown, and cached readings keep their original freshness.
struct ProviderMenuBarReading: Equatable, Sendable {
    let source: SourceKey
    let displayName: String
    let window: UsageWindow?
    let isStale: Bool
    let updatedAt: Date?

    init(state: ProviderState, at now: Date) {
        source = state.id
        displayName = state.displayName
        let snapshot = state.snapshot
        let valid = snapshot?.status == .available && (snapshot?.dataDate ?? .distantFuture) <= now
        window = valid ? snapshot?.windows.asOf(now).mostRelevant : nil
        isStale = state.failure != nil || (snapshot?.isStale(at: now) ?? false)
        updatedAt = snapshot?.dataDate
    }

    var usage: UsagePercentage? { window?.usage }

    /// An icon opens the existing popover with this account first. The rest
    /// of the current set stays accessible, including its settings controls.
    static func focusing(_ source: SourceKey?, in states: [ProviderState]) -> [ProviderState] {
        guard let source, let index = states.firstIndex(where: { $0.id == source }), index != 0 else { return states }
        var result = states
        result.insert(result.remove(at: index), at: 0)
        return result
    }
}
