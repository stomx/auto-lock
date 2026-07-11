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
            AppLog.system.error("dlopen(login.framework) failed: \(CStringSafe.string(from: dlerror(), fallback: "no error info"), privacy: .public)")
            return false
        }
        defer { dlclose(handle) }

        guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
            AppLog.system.error("SACLockScreenImmediate symbol not found")
            return false
        }
        typealias SACLockFn = @convention(c) () -> Int32
        let fn = unsafeBitCast(sym, to: SACLockFn.self)
        let rc = fn()
        if rc != 0 {
            AppLog.system.error("SACLockScreenImmediate returned \(rc, privacy: .public)")
        }
        return rc == 0
    }

    public static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
