import AppKit
import SwiftUI
import Testing
@testable import UsageNow

@MainActor
struct PresentationLayoutTests {
    @Test func largeWidgetContentFitsStandardHeight() throws {
        let now = WidgetPreviewFixtures.now
        let providers = [.codex, .claudeCode, .windsurf, .cursor, .copilot].map { (id: ProviderID) in
            WidgetProviderSnapshot(provider: id, accountName: "Studio", windows: WidgetPreviewFixtures.claude.windows, updatedAt: now)
        }
        let snapshot = WidgetPreviewFixtures.snapshot(providers)
        for language in [AppLanguage.en, .nl, .ru] {
            let view = NSHostingView(rootView: LargeUsageWidgetView(snapshot: snapshot, now: now)
                .appLanguage(language)
                .frame(width: 297)
                .fixedSize(horizontal: false, vertical: true))
            #expect(view.fittingSize.height <= 313, "Large widget content must fit inside a 329×345 widget with margins")
        }
    }
}
