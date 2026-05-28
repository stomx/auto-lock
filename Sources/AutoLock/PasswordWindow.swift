import AppKit
import SwiftUI
import Carbon

/// Standalone window for the auto-unlock password sheet.
///
/// Same reasoning as `PickerWindow`: a SwiftUI `.sheet` attached to a
/// `MenuBarExtra(.window)` popover dismisses itself the moment the SecureField
/// takes focus, because the popover treats focus changes as outside clicks.
/// Hosting the form in its own NSWindow keeps the password field interactive.
@MainActor
enum PasswordWindow {
    private static var window: NSWindow?
    private static var previousInputSource: TISInputSource?

    static func show(onSaved: @escaping () -> Void) {
        // Hide any open MenuBarExtra popover. While the popover is key, AppKit
        // routes alphabetic keystrokes to its menu-shortcut handler so they
        // never reach our SecureField — numbers/symbols slip through, hence
        // the "only numpad works" symptom. We use orderOut (not close) to
        // avoid breaking the MenuBarExtra window lifecycle, which would
        // prevent the menu from re-opening later.
        hideMenuBarPopover()

        // Force ABC input source. Korean/Japanese/Chinese IMEs intercept key
        // events for composition, so SecureField receives empty strings until
        // the user manually toggles to ABC. Saving the previous source lets
        // us restore the user's choice when the window closes.
        switchToASCIIInput()

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = ASCIIOnlyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "로그인 암호"
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(
            rootView: PasswordSheetView(
                hasPassword: KeychainStore.hasPassword(),
                onSave: { pw in
                    if KeychainStore.save(password: pw) {
                        onSaved()
                    }
                    close()
                },
                onDelete: {
                    KeychainStore.delete()
                    onSaved()
                    close()
                },
                onCancel: { close() }
            )
        )
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    static func close() {
        restoreInputSource()
        window?.orderOut(nil)
        window = nil
    }

    private static func hideMenuBarPopover() {
        for w in NSApp.windows where w.isVisible {
            let className = String(describing: type(of: w))
            if className.contains("StatusBar") || className.contains("Popover") || className.contains("MenuBarExtra") {
                w.orderOut(nil)
            }
        }
    }

    // MARK: - IME switching

    private static func switchToASCIIInput() {
        if previousInputSource == nil,
           let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            previousInputSource = current
        }
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            TISSelectInputSource(ascii)
        }
    }

    private static func restoreInputSource() {
        if let prev = previousInputSource {
            TISSelectInputSource(prev)
            previousInputSource = nil
        }
    }
}

/// NSWindow that drops any in-progress IME composition the moment it becomes
/// key. Some Korean IMEs hold marked text from a prior responder and that
/// state can swallow alphabet input even after the app-level TIS swap above.
/// The actual ASCII-only enforcement lives on the SecureField field editor
/// (`ASCIIOnlySecureTextField`); this class just opens the door cleanly.
private final class ASCIIOnlyWindow: NSWindow {
    override func becomeKey() {
        super.becomeKey()
        if let responder = firstResponder as? NSTextView {
            responder.unmarkText()
            responder.inputContext?.discardMarkedText()
        }
    }
}
