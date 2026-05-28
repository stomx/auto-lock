import Foundation
import ServiceManagement

/// Wraps SMAppService.mainApp (macOS 13+) so users can toggle "open at login"
/// from inside the menu bar. SMAppService persists the preference in the
/// system's launch services database — no helper plist or LaunchAgent file
/// to ship.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Errors are logged via NSLog so the menu can
    /// report a generic failure without leaking the underlying reason.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
            return true
        } catch {
            NSLog("AutoLock: LaunchAtLogin toggle failed: \(error)")
            return false
        }
    }
}
