import Foundation
import Observation

/// A single, bounded display clock shared by all provider icons. A TimelineView
/// inside a MenuBarExtra label can continuously invalidate SwiftUI's status-item
/// image renderer, blocking the main thread and exhausting memory. The clock
/// lives outside that renderer and never starts a provider request.
@Observable @MainActor
final class MenuBarClock {
    private(set) var now: Date
    @ObservationIgnored private var task: Task<Void, Never>?
    private let interval: Duration

    init(interval: Duration = .seconds(15), now: Date = .now) {
        precondition(interval > .zero)
        self.interval = interval
        self.now = now
    }

    var isRunning: Bool { task != nil }

    func setActive(_ active: Bool) {
        guard active else {
            task?.cancel()
            task = nil
            return
        }
        guard task == nil else { return }
        now = .now
        task = Task { [weak self, interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard !Task.isCancelled else { return }
                self?.now = .now
            }
        }
    }

    deinit { task?.cancel() }
}
