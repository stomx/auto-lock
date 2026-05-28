import Foundation
import AppKit

enum ScreenLocker {
    /// Trigger the standard macOS screen lock.
    ///
    /// We call `SACLockScreenImmediate` from the private login.framework, which is
    /// the same code path Apple uses for "Lock Screen" in the menu bar and for
    /// Ctrl+Cmd+Q. The legacy `User.menu/CGSession -suspend` binary was removed
    /// in recent macOS releases, so we don't fall back to it.
    @discardableResult
    static func lock() -> Bool {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
            RTLD_NOW
        ) else {
            NSLog("AutoLock: dlopen(login.framework) failed: \(String(cString: dlerror()))")
            return false
        }
        defer { dlclose(handle) }

        guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
            NSLog("AutoLock: SACLockScreenImmediate symbol not found")
            return false
        }
        typealias SACLockFn = @convention(c) () -> Int32
        let fn = unsafeBitCast(sym, to: SACLockFn.self)
        let rc = fn()
        if rc != 0 {
            NSLog("AutoLock: SACLockScreenImmediate returned \(rc)")
        }
        return rc == 0
    }

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
