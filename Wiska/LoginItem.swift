import Foundation
import Observation
import ServiceManagement

/// Launch at login via the system's login items. The truth lives in macOS, not in UserDefaults.
@MainActor @Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var error: String?

    /// The login item points at this copy of the app; moving it later needs re-enabling.
    var isOutsideApplications: Bool { !Bundle.main.bundlePath.hasPrefix("/Applications/") }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
