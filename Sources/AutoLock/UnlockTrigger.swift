import Foundation
import AppKit
import ApplicationServices

/// Attempts to bring a locked Mac all the way to the desktop by waking the
/// display and typing the saved password into the loginwindow prompt.
///
/// Whether the keystrokes actually reach the lock screen depends on the macOS
/// version and the user's security settings. On modern macOS the typed input
/// is delivered to loginwindow when Accessibility permission is granted; on
/// some hardened configurations the OS drops them silently. We surface the
/// outcome via the result enum so the UI can fall back to "wake-only".
enum UnlockTrigger {
    enum Result {
        case unlocked
        case noPassword
        case noAccessibility
        case dispatched   // keys were sent; we can't observe whether loginwindow accepted them
    }

    /// Returns true when the system reports that this process is allowed to
    /// post synthetic keyboard events. We never *prompt* automatically — the
    /// caller decides when to show the system prompt to avoid surprising the user.
    static func hasAccessibility(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open the System Settings pane where the user can grant Accessibility.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Wake the display, then post the saved password followed by Return.
    /// Caller must have already verified `ScreenLocker.isScreenLocked()`.
    static func attempt() -> Result {
        guard let password = KeychainStore.load() else { return .noPassword }
        guard hasAccessibility(prompt: false) else { return .noAccessibility }

        // Wake first so loginwindow advances from clock face to the password
        // prompt. We give the WindowServer a moment to bring the display up
        // before posting keystrokes — too eager and the first characters are
        // dropped on the way through.
        _ = DisplayWaker.wake()

        DispatchQueue.main.asyncAfter(deadline: .now() + LockTuning.unlockKeystrokeDelaySeconds) {
            postString(password)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                postReturnKey()
            }
        }
        return .dispatched
    }

    // MARK: - Synthetic keystrokes

    private static func postString(_ string: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // CGEventKeyboardSetUnicodeString lets us avoid building a keycode map
        // for every locale and special character. Each character is sent as a
        // distinct down/up event so loginwindow's input handler doesn't merge
        // them into one composite event.
        for char in string {
            let utf16 = Array(String(char).utf16)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            utf16.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                    up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                }
            }
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private static func postReturnKey() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // 36 == kVK_Return
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
