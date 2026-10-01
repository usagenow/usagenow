import Foundation

/// Something worth a notification about one usage window.
struct LimitNotice: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// The window is down to a threshold. Carries the usage as read.
        case low(UsagePercentage)
        /// A window the person was warned about has reset.
        case reset
    }

    var provider: ProviderID
    var window: UsageWindowKind
    var scope: String?
    var kind: Kind
    /// When the window resets, for a `low` notice. `nil` if unknown.
    var resetsAt: Date?

    /// Identifies the window, so a later notice about it replaces an earlier
    /// one of the same kind instead of piling up.
    var windowKey: String { LimitNoticePlanner.key(provider, kind: window, scope: scope) }

    var identifier: String {
        switch kind {
        case .low: "limit.low.\(windowKey)"
        case .reset: "limit.reset.\(windowKey)"
        }
    }
}

/// Decides when a limit is worth a notification. Pure: it's handed what was
/// read and what it already said, and answers with what to do.
///
/// The rules, chosen to stay quiet:
/// - one notice when a window is down to 20% left, one more at 5%;
/// - a window first seen below both thresholds gets one notice, not two;
/// - nothing is repeated until that window resets;
/// - "has reset" is said only about a window that got a warning — otherwise
///   it would arrive every five hours for no reason.
enum LimitNoticePlanner {
    /// Percent left at which a notice is sent, largest first.
    static let thresholds = [20, 5]

    /// A reset time read again a little differently isn't a new reset time.
    static let resetTolerance: TimeInterval = 60

    /// What has been said about one window, kept until it resets.
    struct WindowMemory: Codable, Equatable, Sendable {
        /// The lowest threshold a notice was sent for.
        var notified: Int
        var resetsAt: Date?
        /// Whether a "has reset" notice is waiting for `resetsAt`.
        var isResetScheduled = false
    }

    typealias Memory = [String: WindowMemory]

    enum Action: Equatable, Sendable {
        case deliver(LimitNotice)
        /// Deliver at a date, whether or not UsageNow is still running.
        case schedule(LimitNotice, at: Date)
        /// Withdraw a scheduled notice that hasn't been delivered.
        case cancel(identifier: String)
    }

    static func key(_ provider: ProviderID, kind: UsageWindowKind, scope: String?) -> String {
        "\(provider.rawValue)|\(UsageWindow(kind: kind, scope: scope).id)"
    }

    static func plan(snapshots: [ProviderSnapshot], memory: inout Memory, now: Date) -> [Action] {
        var actions: [Action] = []
        var seen: Set<String> = []

        for snapshot in snapshots where snapshot.status == .available {
            for window in snapshot.windows {
                let key = key(snapshot.provider, kind: window.kind, scope: window.scope)
                seen.insert(key)
                func notice(_ kind: LimitNotice.Kind) -> LimitNotice {
                    LimitNotice(provider: snapshot.provider, window: window.kind, scope: window.scope, kind: kind, resetsAt: window.resetsAt)
                }

                // A window whose reset time has passed is a new window. A
                // scheduled notice has said so already; without one — the
                // reset time wasn't known when the warning went out — say so now.
                if let remembered = memory[key], let resetsAt = remembered.resetsAt, resetsAt <= now {
                    if !remembered.isResetScheduled { actions.append(.deliver(notice(.reset))) }
                    memory[key] = nil
                }

                guard let usage = window.usage else { continue }
                let remaining = usage.remainingDisplayValue
                let crossed = thresholds.filter { remaining <= $0 }.min()

                guard var remembered = memory[key] else {
                    guard let crossed else { continue }
                    var entry = WindowMemory(notified: crossed, resetsAt: window.resetsAt)
                    actions.append(.deliver(notice(.low(usage))))
                    if let resetsAt = window.resetsAt, resetsAt > now {
                        actions.append(.schedule(notice(.reset), at: resetsAt))
                        entry.isResetScheduled = true
                    }
                    memory[key] = entry
                    continue
                }

                guard let crossed else {
                    // Back above every threshold before the reset time: the
                    // limit was reset early, or it never had a reset time.
                    if remembered.isResetScheduled { actions.append(.cancel(identifier: notice(.reset).identifier)) }
                    actions.append(.deliver(notice(.reset)))
                    memory[key] = nil
                    continue
                }

                if crossed < remembered.notified {
                    actions.append(.deliver(notice(.low(usage))))
                    remembered.notified = crossed
                }
                if let resetsAt = window.resetsAt, resetsAt > now,
                   abs(resetsAt.timeIntervalSince(remembered.resetsAt ?? .distantPast)) > resetTolerance {
                    actions.append(.schedule(notice(.reset), at: resetsAt))
                    remembered.resetsAt = resetsAt
                    remembered.isResetScheduled = true
                }
                memory[key] = remembered
            }
        }

        // A window that's no longer reported — its provider was turned off,
        // or the tool stopped listing it — is forgotten once it has reset.
        for (key, remembered) in memory where !seen.contains(key) {
            if let resetsAt = remembered.resetsAt, resetsAt <= now { memory[key] = nil }
        }
        return actions
    }

    /// Forgets windows of providers that are no longer tracked, withdrawing
    /// what was scheduled for them.
    static func forget(providersOtherThan enabled: Set<ProviderID>, memory: inout Memory) -> [Action] {
        var actions: [Action] = []
        for (key, remembered) in memory {
            guard let provider = key.split(separator: "|").first.flatMap({ ProviderID(rawValue: String($0)) }),
                  !enabled.contains(provider) else { continue }
            if remembered.isResetScheduled { actions.append(.cancel(identifier: "limit.reset.\(key)")) }
            memory[key] = nil
        }
        return actions
    }
}

extension LimitNotice {
    /// "Claude Code: 18% of the 5-hour limit left".
    func title(style: UsageAmountStyle) -> String {
        let name = provider.displayName
        let limit = scope.map { "\(window.title) \($0)" } ?? window.title
        switch kind {
        case .reset:
            return String(localized: "\(name): \(limit) limit has reset", comment: "Notification title, e.g. Claude Code: 5-hour limit has reset")
        case .low(let usage) where usage.remainingDisplayValue == 0:
            return String(localized: "\(name): \(limit) limit reached", comment: "Notification title, e.g. Claude Code: 5-hour limit reached")
        case .low(let usage):
            switch style {
            case .remaining:
                return String(localized: "\(name): \(UsageFormatter.remainingPercent(usage)) of the \(limit) limit left", comment: "Notification title, e.g. Claude Code: 18% of the 5-hour limit left")
            case .used:
                return String(localized: "\(name): \(UsageFormatter.percent(usage)) of the \(limit) limit used", comment: "Notification title, e.g. Claude Code: 82% of the 5-hour limit used")
            }
        }
    }

    /// "Resets in 1h 24m", or nothing when there's nothing true to add.
    func body(now: Date, formatter: ResetTimeFormatter = ResetTimeFormatter()) -> String {
        switch kind {
        case .reset:
            return String(localized: "The full limit is available again.")
        case .low:
            guard let resetsAt, resetsAt > now else { return "" }
            return formatter.resetDescription(for: resetsAt, now: now)
        }
    }
}
