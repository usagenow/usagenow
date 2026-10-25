import AppKit
import Observation
import UserNotifications

/// Where notices go. The system's notification center in the app; a
/// recorder in tests.
@MainActor
protocol LimitNoticeDelivering: AnyObject {
    func deliver(identifier: String, title: String, body: String, at date: Date?)
    func cancel(identifiers: [String])
    func cancelAll()
}

/// Sends notifications about limits: when little is left, and when a limit
/// the person was warned about resets.
///
/// Off unless turned on in Settings. Notifications are local — macOS shows
/// them, and nothing is sent anywhere. What has already been said is kept
/// in preferences, so relaunching the app doesn't say it again.
@Observable
@MainActor
final class LimitNotifier {
    enum Permission: Sendable, Equatable {
        case unknown
        case allowed
        /// Notifications are off for UsageNow in System Settings.
        case denied
    }

    private(set) var permission = Permission.unknown

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let delivery: any LimitNoticeDelivering
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var memory: LimitNoticePlanner.Memory
    @ObservationIgnored private(set) var isEnabled = false
    @ObservationIgnored private var configuration: NotificationPolicy?
    @ObservationIgnored private var timeZone: String?

    private static let memoryKey = "limitNotifications.memory"

    init(
        defaults: UserDefaults = .standard,
        delivery: any LimitNoticeDelivering = SystemNoticeDelivery(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.delivery = delivery
        self.now = now
        configuration = defaults.data(forKey: "limitNotifications.policy")
            .flatMap { try? JSONDecoder().decode(NotificationPolicy.self, from: $0) } ?? NotificationPolicy()
        timeZone = defaults.string(forKey: "limitNotifications.timeZone") ?? TimeZone.autoupdatingCurrent.identifier
        memory = defaults.data(forKey: Self.memoryKey)
            .flatMap { try? JSONDecoder().decode(LimitNoticePlanner.Memory.self, from: $0) } ?? [:]
    }

    /// Turning notifications off withdraws what was scheduled and forgets
    /// what was said, so turning them on again starts fresh.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            delivery.cancelAll()
            memory = [:]
            save()
        }
    }

    /// Looks at fresh readings and sends whatever they call for.
    func update(snapshots: [ProviderSnapshot], enabledProviders: Set<ProviderID>, style: UsageAmountStyle,
                policy: NotificationPolicy = NotificationPolicy(), activeSources: Set<SourceKey>? = nil) {
        guard isEnabled else { return }
        let date = now()
        let before = memory
        if configuration != policy || timeZone != TimeZone.autoupdatingCurrent.identifier {
            // Also reconciles schedules left by an earlier app version.
            delivery.cancelAll()
            for key in memory.keys {
                if (memory[key]?.resetsAt ?? .distantFuture) > date {
                    memory[key]?.isResetScheduled = false
                    memory[key]?.resetSuppressed = nil
                }
            }
            configuration = policy
            timeZone = TimeZone.autoupdatingCurrent.identifier
            defaults.set(try? JSONEncoder().encode(policy), forKey: "limitNotifications.policy")
            defaults.set(timeZone, forKey: "limitNotifications.timeZone")
        }
        let notifying = enabledProviders.filter { policy.rule(for: $0).enabled }
        var actions = LimitNoticePlanner.forget(providersOtherThan: notifying, memory: &memory)
        // Deleted accounts cannot leave a reset scheduled for another identity.
        // The registry includes sources still loading after launch. An absent
        // snapshot is not evidence that its account was removed.
        let present = activeSources ?? Set(snapshots.map(\.id))
        for (key, entry) in memory {
            let source = key.split(separator: "|").first.map(String.init)
            if let source, !present.contains(where: { "\($0)" == source }) {
                if entry.isResetScheduled { actions.append(.cancel(identifier: "limit.reset.\(key)")) }
                memory[key] = nil
            }
        }
        actions += LimitNoticePlanner.plan(snapshots: snapshots, memory: &memory, now: date, policy: policy)
        if memory != before { save() }

        for action in actions {
            switch action {
            case .deliver(let notice):
                delivery.deliver(identifier: notice.identifier, title: notice.title(style: style), body: notice.body(now: date), at: nil)
            case .schedule(let notice, let at):
                delivery.deliver(identifier: notice.identifier, title: notice.title(style: style), body: notice.body(now: at), at: at)
            case .cancel(let identifier):
                delivery.cancel(identifiers: [identifier])
            }
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(memory), forKey: Self.memoryKey)
    }

    // MARK: Permission

    /// Asks macOS for permission to show notifications. macOS asks the
    /// person once; after that this only reads the answer.
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshPermission()
    }

    func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permission = switch status {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        default: .unknown
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Delivers through `UNUserNotificationCenter`.
@MainActor
final class SystemNoticeDelivery: NSObject, LimitNoticeDelivering, UNUserNotificationCenterDelegate {
    private var isDelegateSet = false

    /// Touched only when there's something to deliver, so a build that
    /// never notifies never talks to the notification center.
    private var center: UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        if !isDelegateSet {
            center.delegate = self
            isDelegateSet = true
        }
        return center
    }

    func deliver(identifier: String, title: String, body: String, at date: Date?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = date.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false) }
        // The same identifier replaces an earlier request for the same window.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { Log.app.notice("Couldn’t post a limit notification: \(error.localizedDescription)") }
        }
    }

    func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// UsageNow has no windows to be "in front" with, but macOS counts it as
    /// frontmost while its menu bar window or Settings is open — and hides
    /// notifications from the frontmost app unless asked not to.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
