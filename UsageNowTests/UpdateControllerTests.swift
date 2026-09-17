import Foundation
import Testing

@testable import UsageNow

@MainActor
struct UpdateControllerTests {
    /// A build with no signing key must not start the updater: without the
    /// key there is nothing to verify an update against.
    @Test func aBuildWithoutASigningKeyCannotUpdate() {
        for key in [nil, "", "   "] {
            let updates = UpdateController(publicKey: key)
            #expect(!updates.isSupported)
            #expect(!updates.canCheckForUpdates)
            #expect(!updates.checksAutomatically)
        }
    }

    @Test func anUnsupportedBuildSaysSoInsteadOfShowingACheckTime() {
        let updates = UpdateController(publicKey: nil)
        #expect(updates.lastCheckedDescription == "Updates are off in this build")
    }

    /// Turning the switch on in such a build must not pretend it worked.
    @Test func turningUpdatesOnHasNoEffectWithoutAKey() {
        let updates = UpdateController(publicKey: nil)
        updates.checksAutomatically = true
        #expect(!updates.checksAutomatically)
    }
}
