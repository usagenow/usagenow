import Foundation
import Testing

@testable import UsageNow

struct AcknowledgementTests {
    /// Every bundled dependency needs its notice in the app, whole.
    @Test func sparklesLicenseIsIncludedWithItsBundledComponents() throws {
        let sparkle = try #require(Acknowledgement.all.first { $0.name == "Sparkle" })
        for notice in ["Andy Matuschak", "Colin Percival", "Yuta Mori", "Orson Peters", "Mark Hamlin"] {
            #expect(sparkle.text.contains(notice), "Missing the notice for \(notice)")
        }
    }
}
