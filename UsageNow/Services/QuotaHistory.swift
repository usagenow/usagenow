import Foundation

/// Small, bounded local quota history. Window labels may name a model group;
/// no credentials, paths, account names, prompts or activity records are kept.
/// Never sent to telemetry or the widget.
@MainActor
final class QuotaHistory {
    private static let key = "quotaObservations.v1"
    private let defaults: UserDefaults?
    private var readings: [String: [QuotaPace]]

    /// Tests and previews use memory only; the live app supplies its domain.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        readings = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: [QuotaPace]].self, from: $0) } ?? [:]
    }

    func observe(_ snapshot: ProviderSnapshot, at now: Date) -> [QuotaPace] {
        let key = snapshot.id.description
        let old = readings[key] ?? []
        guard snapshot.status == .available, snapshot.quotaUnavailableReason == nil,
              !snapshot.isStale(at: now), snapshot.dataDate <= now else { return [] }
        let date = snapshot.dataDate
        let current = snapshot.windows.compactMap { window -> QuotaPace? in
            guard let duration = QuotaPace.duration(of: window.kind),
                  let reset = window.resetsAt, reset > now,
                  reset.timeIntervalSince(date) <= duration + 60,
                  let used = window.usage else { return nil }
            var pace = old.first { $0.id == window.id && $0.window.resetsAt == reset }
                ?? QuotaPace(window: window, points: [])
            pace.window = window
            if let last = pace.points.last {
                // A cached timestamp is not a new independent observation.
                if date <= last.date {
                    // A correction at the same capture time is not a new
                    // measurement and invalidates the old trend.
                    if used != last.used { pace.points = [.init(date: date, used: used)] }
                    return pace
                }
                if used < last.used || date.timeIntervalSince(last.date) > QuotaPace.maximumGap {
                    pace.points = []
                } else if date.timeIntervalSince(last.date) < 60 {
                    pace.points.removeLast()
                }
            }
            pace.points.append(.init(date: date, used: used))
            pace.points = Array(pace.points.suffix(QuotaPace.maximumPoints))
            return pace
        }
        readings[key] = current
        // Account count and window count are not controlled by remote data.
        readings = readings.mapValues { Array($0.filter { ($0.window.resetsAt ?? .distantPast) > now }.prefix(12)) }
            .filter { !$0.value.isEmpty }
        if readings.count > 128 { readings = [key: current] }
        persist()
        return current
    }

    func remove(_ key: SourceKey) {
        readings.removeValue(forKey: key.description)
        persist()
    }

    func retain(_ keys: Set<SourceKey>) {
        let allowed = Set(keys.map(\.description))
        readings = readings.filter { allowed.contains($0.key) }
        persist()
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(readings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
