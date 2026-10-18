import Foundation
import Testing

@testable import UsageNow

struct AcknowledgementTests {
    /// Notices remain in every distribution, without occupying About.
    @Test func dependencyLicensesAreBundledInFull() throws {
        let file = try #require(Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt"))
        let notices = try String(contentsOf: file, encoding: .utf8)
        for notice in ["Peter Steinberger", "Andy Matuschak", "Colin Percival", "Yuta Mori", "Orson Peters", "Mark Hamlin"] {
            #expect(notices.contains(notice), "Missing the notice for \(notice)")
        }
        #expect(notices.contains("Redistributions in binary form must reproduce"))
        #expect(notices.contains("The above copyright notice and this permission notice"))
    }

    @Test func aboutShowsUsageNowsOwnLicense() {
        #expect(UsageNowLicense.text.contains("Copyright (c) 2026 UsageNow"))
        #expect(!UsageNowLicense.text.contains("Sparkle"))
        #expect(!UsageNowLicense.text.contains("CodexBar"))
    }
}
