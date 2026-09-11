import Foundation

/// Reads and writes the widget snapshot in the App Group container.
///
/// The main app writes; the widget only reads. Nothing else is stored
/// there, and the file holds no credentials or provider files.
struct WidgetSnapshotStore: Sendable {
    static let fileName = "widget-snapshot.json"

    /// The App Group both targets declare. Read from the bundle so the
    /// build settings stay the single source of truth.
    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "UsageNowAppGroupIdentifier") as? String
            ?? "group.com.usagenow.UsageNow"
    }

    /// `nil` when the App Group container isn't available — for example an
    /// ad-hoc signed build without the entitlement. Callers degrade quietly.
    static func shared() -> WidgetSnapshotStore? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            Log.app.debug("App Group container unavailable; widget snapshot disabled")
            return nil
        }
        return WidgetSnapshotStore(directory: container)
    }

    let directory: URL

    var fileURL: URL { directory.appending(path: Self.fileName) }

    func write(_ snapshot: WidgetSnapshot) throws {
        let data = try JSONEncoder.widget.encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// The stored snapshot, or `nil` when it's missing, unreadable,
    /// corrupt, or written by a newer app version.
    func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? JSONDecoder.widget.decode(WidgetSnapshot.self, from: data) else {
            Log.app.debug("Widget snapshot couldn't be decoded")
            return nil
        }
        guard snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion else {
            Log.app.debug("Widget snapshot uses a newer schema")
            return nil
        }
        return snapshot
    }

    func removeSnapshot() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension JSONEncoder {
    static var widget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var widget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
