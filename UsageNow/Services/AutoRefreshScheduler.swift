import Foundation

/// Runs an action on a fixed interval until rescheduled or stopped.
///
/// Intervals are minutes long on purpose — UsageNow never polls aggressively.
/// Opening the popover triggers its own refresh when data is old.
@MainActor
final class AutoRefreshScheduler {
    private let action: @MainActor () async -> Void
    private var task: Task<Void, Never>?

    init(action: @escaping @MainActor () async -> Void) {
        self.action = action
    }

    /// Replaces the current schedule. `nil` stops automatic refreshing.
    func schedule(every interval: Duration?) {
        task?.cancel()
        task = nil
        guard let interval else { return }

        task = Task { [action] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    func stop() {
        schedule(every: nil)
    }
}
