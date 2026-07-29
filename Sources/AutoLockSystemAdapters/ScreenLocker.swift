import Foundation
import AppKit
import AutoLockCore

public enum ScreenLocker {
    /// Trigger the standard macOS screen lock.
    ///
    /// We call `SACLockScreenImmediate` from the private login.framework, which is
    /// the same code path Apple uses for "Lock Screen" in the menu bar and for
    /// Ctrl+Cmd+Q. The legacy `User.menu/CGSession -suspend` binary was removed
    /// in recent macOS releases, so we don't fall back to it.
    @discardableResult
    public static func lock() -> Bool {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
            RTLD_NOW
        ) else {
            AppLog.record(
                .system,
                level: .error,
                code: "screen_lock_framework_unavailable",
                outcome: .failure,
                message: "macOS login.framework를 열 수 없어 화면 잠금 불가",
                metadata: [
                    "detail": CStringSafe.string(from: dlerror(), fallback: "no_error_info"),
                    "framework": "login.framework"
                ]
            )
            return false
        }
        defer { dlclose(handle) }

        guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
            AppLog.record(
                .system,
                level: .error,
                code: "screen_lock_symbol_unavailable",
                outcome: .failure,
                message: "즉시 잠금 시스템 함수를 찾을 수 없음",
                metadata: ["symbol": "SACLockScreenImmediate"]
            )
            return false
        }
        typealias SACLockFn = @convention(c) () -> Int32
        let fn = unsafeBitCast(sym, to: SACLockFn.self)
        let rc = fn()
        if rc != 0 {
            AppLog.record(
                .system,
                level: .error,
                code: "screen_lock_system_call_failed",
                outcome: .failure,
                message: "macOS 즉시 잠금 시스템 호출 실패",
                metadata: ["return_code": String(rc)]
            )
        }
        return rc == 0
    }

    public static func isScreenLocked() -> Bool {
        screenLockState() == .locked
    }

    /// Unlike the compatibility Boolean above, this preserves an unavailable
    /// CGSession probe as `.unknown` instead of misreporting it as unlocked.
    public static func screenLockState() -> ScreenLockState {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return .unknown
        }
        // WindowServer omits CGSSessionScreenIsLocked while the active session
        // is unlocked; it only adds the Boolean key for a locked session.
        return (dict["CGSSessionScreenIsLocked"] as? Bool) == true ? .locked : .unlocked
    }
}
