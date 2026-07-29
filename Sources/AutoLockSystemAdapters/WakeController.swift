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
public enum DisplayWaker {
    @discardableResult
    public static func wake() -> Bool {
        var assertionID: IOPMAssertionID = IOPMAssertionID(0)
        let reason = "AutoLock proximity wake" as CFString
        let rc = IOPMAssertionDeclareUserActivity(
            reason,
            kIOPMUserActiveLocal,
            &assertionID
        )
        if rc != kIOReturnSuccess {
            AppLog.record(
                .wake,
                level: .error,
                code: "display_wake_system_call_failed",
                outcome: .failure,
                message: "macOS 사용자 활동 선언에 실패해 화면을 깨우지 못함",
                metadata: ["return_code": String(rc)]
            )
            return false
        }
        return true
    }
}
