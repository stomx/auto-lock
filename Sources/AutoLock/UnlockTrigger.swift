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
            // Re-check the lock state at the moment we're about to type. The
            // `.dispatched` decision was made up to `unlockKeystrokeDelaySeconds`
            // ago; during that window the user may have authenticated by Touch
            // ID, Apple Watch, or by typing the password themselves. If we don't
            // re-confirm here, the saved password is injected into whatever now
            // has keyboard focus on the unlocked desktop (a chat box, a notes
            // window, Spotlight…) — leaking the plaintext credential to the
            // wrong place. Only type while the screen is still genuinely locked.
            guard ScreenLocker.isScreenLocked() else {
                AppLog.wake.error("screen unlocked before keystroke injection — aborting to avoid leaking password")
                return
            }
            // `postString` stops mid-word if the screen unlocks during typing
            // and reports whether it finished. We only send Return when the full
            // password was typed into a still-locked screen.
            guard postString(password) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard ScreenLocker.isScreenLocked() else { return }
                postReturnKey()
            }
        }
        return .dispatched
    }

    // MARK: - Synthetic keystrokes

    /// Types `string` into loginwindow one character at a time. Returns `true`
    /// only when every character was posted while the screen stayed locked.
    /// Returns `false` (and stops typing) if the screen unlocks mid-string, so
    /// the caller knows not to follow up with Return — the remaining characters
    /// would otherwise spill onto the now-unlocked desktop.
    ///
    /// The per-character lock re-check and the stop-on-unlock bookkeeping live in
    /// the pure `UnlockKeystrokeSequencer` (unit-tested); this method only wires
    /// in the system pieces — the lock probe and the `CGEvent` synthesis.
    @discardableResult
    private static func postString(_ string: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            AppLog.wake.error("failed to create event source for password keystrokes")
            return false
        }
        // CGEventKeyboardSetUnicodeString lets us avoid building a keycode map
        // for every locale and special character. Each character is sent as a
        // distinct down/up event so loginwindow's input handler doesn't merge
        // them into one composite event.
        let chars = Array(string)
        let result = UnlockKeystrokeSequencer.runTyping(
            characterCount: chars.count,
            // Re-probed before every character: bail the instant the screen is
            // no longer locked, so the rest of the password can't leak into
            // whatever app now holds keyboard focus on the unlocked desktop.
            isScreenLocked: { ScreenLocker.isScreenLocked() },
            emit: { index in
                let utf16 = Array(String(chars[index]).utf16)
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    // Surface the failure instead of dropping a character silently —
                    // the auto-unlock will be incomplete and the user must fall back
                    // to manual auth.
                    AppLog.wake.error("failed to create key event for password character")
                    return
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
        )
        if !result.completed {
            AppLog.wake.error("screen unlocked mid-typing — aborted after \(result.typedCount) password keystrokes")
        }
        return result.completed
    }

    private static func postReturnKey() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            AppLog.wake.error("failed to create event source for Return key")
            return
        }
        // 36 == kVK_Return
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            AppLog.wake.error("failed to create Return key event")
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
