import Foundation
import Observation
import ServiceManagement

/// Registers UsageNow as a login item through `SMAppService`.
///
/// The system owns this setting — users can also change it in
/// System Settings › General › Login Items — so it's read back from
/// `SMAppService` rather than stored in preferences.
@Observable
@MainActor
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        self.status = service.status
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// The user must allow the login item in System Settings.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshStatus()
    }

    func refreshStatus() {
        status = service.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
