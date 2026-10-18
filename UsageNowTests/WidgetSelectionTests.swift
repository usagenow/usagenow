import Foundation
import Testing
@testable import UsageNow

@MainActor
struct WidgetSelectionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(_ provider: ProviderID = .codex, account: AccountTag? = nil) -> ProviderState {
        ProviderState(provider: provider, account: account, snapshot: Fixtures.snapshot(provider, at: now))
    }

    @Test func automaticKeepsExistingWidgetBehavior() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [state(), state(.claudeCode)], enabledProviders: [.codex, .claudeCode], generatedAt: now)
        #expect(snapshot.selecting([]) == snapshot)
    }

    @Test func selectionUsesStableLocalIdentityAndPreservesOrder() throws {
        let personal = state()
        let work = state(account: AccountTag(id: "local-random-uuid", name: "Work"))
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [personal, work], enabledProviders: [.codex], generatedAt: now)
        let id = WidgetSnapshotWriter.selectionID(for: work)
        let selection = snapshot.selecting([id, "codex", id])
        #expect(selection.providers.map(\.id) == [id, "codex"])
        #expect(selection.providers.first?.displayName == "Codex · Work")
        var renamed = work
        renamed.account?.name = "Studio"
        #expect(WidgetSnapshotWriter.selectionID(for: renamed) == id)
        #expect(WidgetSnapshotWriter.selectionID(for: state(.claudeCode, account: work.account)) != id)
        let serialized = String(decoding: try JSONEncoder.widget.encode(snapshot), as: UTF8.self)
        #expect(!serialized.contains("local-random-uuid"))
    }

    @Test func removedOrDisabledAccountNeverFallsBackToAnother() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [state()], enabledProviders: [.codex], generatedAt: now)
        #expect(snapshot.selecting(["codex:deleted"]).state == .providers([]))
        #expect(snapshot.selecting(["codex:deleted", "codex"]).providers.map(\.id) == ["codex"])
    }

    @Test func selectionDoesNotChangeFreshnessOrResetHandling() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(states: [state()], enabledProviders: [.codex], generatedAt: now)
        let selected = snapshot.selecting(["codex"]).asOf(now.addingTimeInterval(3_601))
        #expect(selected.generatedAt == now)
        #expect(selected.providers.first?.updatedAt == now)
        #expect(selected.providers.first?.windows.first?.usage == nil)
        #expect(selected.providers.first?.isStale(at: now.addingTimeInterval(3_601)) == true)
    }
}
