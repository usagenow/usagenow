import Foundation

/// Versioned public CLI contract. Only explicitly copied display values escape.
struct CLIStatus: Codable, Equatable {
    struct Window: Codable, Equatable {
        var kind: String
        var durationMinutes: Int?
        var scope: String?
        var remainingPercent: Double?
        var resetsAt: Date?
    }
    struct Provider: Codable, Equatable {
        var id: String
        var provider: String
        var accountName: String?
        var plan: String?
        var updatedAt: Date?
        var stale: Bool
        var quotaUnavailableReason: String?
        var windows: [Window]
    }
    var schemaVersion = 1
    var generatedAt: Date
    var readAt: Date
    var state: String
    var stale: Bool
    var providers: [Provider]

    static func read(_ data: Data, now: Date) throws -> CLIStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(SavedSnapshot.self, from: data)
        guard saved.schemaVersion == 1 else { throw CLIError.unsupportedSnapshot }
        func stale(_ date: Date?) -> Bool {
            guard let date else { return true }
            return now.timeIntervalSince(date) > 600 || date.timeIntervalSince(now) > 60
        }
        return CLIStatus(generatedAt: saved.generatedAt, readAt: now, state: saved.state.name,
                         stale: stale(saved.generatedAt), providers: saved.state.providers.map { provider in
            Provider(id: provider.selectionID ?? (provider.accountName.map { provider.provider + " · " + $0 } ?? provider.provider), provider: provider.provider,
                     accountName: provider.accountName, plan: provider.planName, updatedAt: provider.updatedAt,
                     stale: stale(provider.updatedAt ?? saved.generatedAt), quotaUnavailableReason: provider.quotaUnavailableReason,
                     windows: provider.windows.map { window in
                let reset = window.resetsAt.map { $0 <= now } ?? false
                return Window(kind: window.kind.name, durationMinutes: window.kind.minutes, scope: window.scope,
                              remainingPercent: reset ? nil : window.usage.map { 100 - min(100, max(0, $0)) }, resetsAt: window.resetsAt)
            })
        })
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    var text: String {
        let date = ISO8601DateFormatter().string(from: generatedAt)
        var lines = ["UsageNow · snapshot \(date)\(stale ? " · STALE — open UsageNow to update" : "")"]
        if providers.isEmpty { lines.append(state == "noProvidersEnabled" ? "No providers enabled." : "No providers detected. Open UsageNow.") }
        for provider in providers {
            // Keep provider-supplied labels on one terminal line, without ANSI escapes.
            func clean(_ value: String) -> String { String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }) }
            let account = provider.accountName.map { " · \(clean($0))" } ?? ""
            lines.append("\(clean(provider.provider))\(account)\(provider.stale ? " · STALE" : "")")
            if provider.windows.isEmpty { lines.append("  Limits unavailable.") }
            for window in provider.windows {
                let scope = window.scope.map { " · \(clean($0))" } ?? ""
                let remaining = window.remainingPercent.map { String(format: "%.1f%% left", $0) } ?? "unknown"
                let reset = window.resetsAt.map { " · reset \(ISO8601DateFormatter().string(from: $0))" } ?? ""
                lines.append("  \(window.kind)\(scope): \(remaining)\(reset)")
            }
            if let reason = provider.quotaUnavailableReason { lines.append("  \(clean(reason))") }
        }
        return lines.joined(separator: "\n")
    }
}

enum CLIError: Error { case unsupportedSnapshot }

// The widget schema is decoded narrowly; unknown/private extra keys are ignored.
private struct SavedSnapshot: Decodable {
    var schemaVersion: Int
    var generatedAt: Date
    var state: State
    struct State: Decodable {
        var name: String
        var providers: [Provider]
        private enum Keys: String, CodingKey { case providers, noProvidersEnabled, noProvidersDetected }
        private struct Payload: Decodable { var _0: [Provider] }
        init(from decoder: any Decoder) throws {
            let value = try decoder.container(keyedBy: Keys.self)
            if value.contains(.providers) {
                name = "providers"
                providers = try value.decode(Payload.self, forKey: .providers)._0
            } else if value.contains(.noProvidersEnabled) {
                name = "noProvidersEnabled"; providers = []
            } else if value.contains(.noProvidersDetected) {
                name = "noProvidersDetected"; providers = []
            } else { throw CLIError.unsupportedSnapshot }
        }
    }
    struct Provider: Decodable {
        var provider: String
        var selectionID: String?
        var accountName: String?
        var planName: String?
        var updatedAt: Date?
        var quotaUnavailableReason: String?
        var windows: [Window]
    }
    struct Window: Decodable {
        var kind: Kind
        var scope: String?
        var usage: Double?
        var resetsAt: Date?
    }
    struct Kind: Decodable {
        var name: String
        var minutes: Int?
        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let length = try? value.decode(Int.self) {
                minutes = length
                name = length == 300 ? "fiveHour" : length == 10080 ? "weekly" : "custom"
            } else { name = try value.decode(String.self) }
        }
    }
}
