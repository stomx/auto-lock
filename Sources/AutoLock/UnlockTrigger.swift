import Foundation
import AppKit
// @preconcurrency suppresses Sendable/global-var warnings from these C SDKs
// (CGEventSource, kAXTrustedCheckOptionPrompt) that aren't yet annotated for
// strict concurrency. Our usage is main-thread and value-only, so it's safe.
@preconcurrency import ApplicationServices
import AutoLockCore

/// Attempts to bring a locked Mac all the way to the desktop by waking the
/// display and typing the saved password into the loginwindow prompt.
///
/// Whether the keystrokes actually reach the lock screen depends on the macOS
/// version and the user's security settings. On modern macOS the typed input
/// is delivered to loginwindow when Accessibility permission is granted; on
/// some hardened configurations the OS drops them silently. We surface the
/// outcome via the result enum so the UI can fall back to "wake-only".
enum UnlockTrigger {
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
    ///
    /// Every synchronous precondition — password, Accessibility, and a usable
    /// `CGEventSource` — is resolved up front via `UnlockPreflight`. We only
    /// reach the async keystroke dispatch once all gates pass, so the returned
    /// outcome is truthful instead of an optimistic `.dispatched` that could
    /// silently fail later.
    ///
    /// Note `.dispatched` means "keystrokes were scheduled", not "the Mac is
    /// unlocked": loginwindow may still drop synthetic events on hardened
    /// configurations. Any per-event creation failure inside the async block is
    /// logged (see `postString` / `postReturnKey`), and the controller wakes the
    /// display as a fallback whenever the synchronous gate fails.
    static func attempt() -> UnlockOutcome {
        let password = KeychainStore.load()
        // Probe event-source availability synchronously for the preflight, but
        // do NOT keep this instance: CGEventSource is non-Sendable and must not
        // be captured by the delayed closures. The helpers create their own.
        let canMakeEventSource = CGEventSource(stateID: .hidSystemState) != nil

        let outcome = UnlockPreflight.decide(
            hasPassword: password != nil,
            hasAccessibility: hasAccessibility(prompt: false),
            canMakeEventSource: canMakeEventSource
        )
        guard outcome == .dispatched, let password else { return outcome }

        // Wake first so loginwindow advances from clock face to the password
        // prompt. We give the WindowServer a moment to bring the display up
        // before posting keystrokes — too eager and the first characters are
        // dropped on the way through.
        _ = DisplayWaker.wake()

        // Only the Sendable `password` crosses the closure boundary.
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
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            NSLog("AutoLock: failed to create event source for password keystrokes")
            return
        }
        // CGEventKeyboardSetUnicodeString lets us avoid building a keycode map
        // for every locale and special character. Each character is sent as a
        // distinct down/up event so loginwindow's input handler doesn't merge
        // them into one composite event.
        for char in string {
            let utf16 = Array(String(char).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                // Surface the failure instead of dropping a character silently —
                // the auto-unlock will be incomplete and the user must fall back
                // to manual auth.
                NSLog("AutoLock: failed to create key event for password character")
                continue
            }
            utf16.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                }
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private static func postReturnKey() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            NSLog("AutoLock: failed to create event source for Return key")
            return
        }
        // 36 == kVK_Return
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            NSLog("AutoLock: failed to create Return key event")
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
