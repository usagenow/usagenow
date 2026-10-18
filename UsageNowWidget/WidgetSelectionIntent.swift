import AppIntents
import Foundation

/// All suggestions come exclusively from the sanitized snapshot.
struct WidgetSourceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider and account")
    static let defaultQuery = WidgetSourceQuery()

    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetSourceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetSourceEntity] {
        let available = sources()
        // Keep missing selections unresolved in the rendered snapshot, not
        // silently replaced with Automatic by an empty entity resolution.
        return identifiers.map { id in
            available.first { $0.id == id } ?? WidgetSourceEntity(id: id, name: String(localized: "Selected account unavailable"))
        }
    }

    func suggestedEntities() async throws -> [WidgetSourceEntity] { sources() }

    private func sources() -> [WidgetSourceEntity] {
        (WidgetSnapshotStore.shared()?.read()?.providers ?? []).map { WidgetSourceEntity(id: $0.id, name: $0.displayName) }
    }
}

struct WidgetSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose providers"
    static let description = IntentDescription("Leave the selection empty to follow UsageNow. Select providers and accounts to personalize this widget.")

    @Parameter(title: "Providers and accounts")
    var sources: [WidgetSourceEntity]?
}
