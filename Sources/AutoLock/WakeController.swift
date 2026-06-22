import Foundation
import IOKit.pwr_mgt
import AutoLockCore

/// Wakes the display when a tracked device comes back into proximity.
///
/// macOS does not let third-party apps bypass the lock screen — the user still
/// has to authenticate with Touch ID, password, or Apple Watch. What we *can*
/// do is light up the display so the auth prompt is already on screen by the
/// time the user reaches the Mac. `IOPMAssertionDeclareUserActivity` is the
/// public API Apple recommends for this; it does not require any extra
/// entitlements or accessibility permissions.
enum DisplayWaker {
    @discardableResult
    static func wake() -> Bool {
        var assertionID: IOPMAssertionID = IOPMAssertionID(0)
        let reason = "AutoLock proximity wake" as CFString
        let rc = IOPMAssertionDeclareUserActivity(
            reason,
            kIOPMUserActiveLocal,
            &assertionID
        )
        if rc != kIOReturnSuccess {
            AppLog.wake.error("IOPMAssertionDeclareUserActivity failed rc=\(rc, privacy: .public)")
            return false
        }
        return true
    }
}
