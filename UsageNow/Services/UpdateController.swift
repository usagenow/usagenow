import AppKit
import Observation
import Sparkle

/// In-app updates, through Sparkle.
///
/// An update is only ever installed when it is signed by the private half of
/// the EdDSA key in `SUPublicEDKey`, which is Sparkle's own check. UsageNow
/// adds one rule of its own: a build without that key doesn't start the
/// updater at all. That way a build made outside the release process — a
/// local build, a fork — can't be told to install anything.
///
/// The updater is deliberately the only part of the app that talks to
/// usagenow.com. It sends no identifiers: Sparkle's system profiling stays
/// off, so a check is a plain request for the appcast.
@MainActor
@Observable
final class UpdateController {
    /// `nil` in a build with no public key, which is every local build.
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let driverDelegate = UpdateUserDriverDelegate()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// False while a check is already running, and in builds without updates.
    private(set) var canCheckForUpdates = false
    private(set) var lastCheckedAt: Date?

    /// Whether Sparkle checks on its own. Off means the user checks manually.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// True when this build can update itself at all.
    var isSupported: Bool { controller != nil }

    /// The key comes from the bundle by default; tests pass one directly.
    convenience init(bundle: Bundle = .main) {
        self.init(publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    }

    init(publicKey: String?) {
        guard let key = publicKey, !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            Log.app.debug("Updates are off: this build has no update signing key")
            controller = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: driverDelegate
        )
        controller.updater.sendsSystemProfile = false
        self.controller = controller

        // Mirror Sparkle's own state instead of keeping a second copy of it.
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            controller.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.lastCheckedAt = updater.lastUpdateCheckDate }
            },
        ]
    }

    /// "Last checked 5 minutes ago", or why there's nothing to check.
    var lastCheckedDescription: String {
        guard isSupported else { return String(localized: "Updates are off in this build") }
        guard let lastCheckedAt else { return String(localized: "Not checked yet") }
        let relative = lastCheckedAt.formatted(.relative(presentation: .named))
        return String(localized: "Last checked \(relative)")
    }

    /// Checks now, showing Sparkle's window whatever the result.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// Brings the app forward before Sparkle shows anything.
///
/// UsageNow has no Dock icon, so an update window would otherwise open behind
/// whatever the person is working in, with nothing to click to find it.
private final class UpdateUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
