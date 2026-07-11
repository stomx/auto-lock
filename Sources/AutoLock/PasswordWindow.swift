import AppKit
import SwiftUI
import Carbon
import AutoLockSystemAdapters

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
    private static let closeDelegate = WindowCloseDelegate { cleanup() }

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
        // Route the titlebar close button through the same cleanup as our
        // buttons. Without this, clicking the red close button bypasses
        // close() — the IME stays forced to ABC and the static `window`
        // reference dangles (so re-opening returns a stale, orderOut window).
        win.delegate = closeDelegate
        win.contentView = NSHostingView(
            rootView: PasswordSheetView(
                hasPassword: KeychainStore.hasPassword(),
                onSave: { pw in
                    if KeychainStore.save(password: pw) {
                        onSaved()
                        close()
                        return true
                    }
                    return false
                },
                onDelete: {
                    if KeychainStore.delete() {
                        onSaved()
                        close()
                        return true
                    }
                    return false
                },
                onCancel: { close() }
            )
        )
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    /// Button-initiated close. Triggers `windowWillClose`, which runs `cleanup()`.
    static func close() {
        window?.close()
    }

    /// Single cleanup path, invoked from `windowWillClose` regardless of whether
    /// the close came from a button or the titlebar. Idempotent: restoring a nil
    /// input source and nil-ing an already-nil window are both no-ops.
    private static func cleanup() {
        restoreInputSource()
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

/// Bridges `NSWindow`'s titlebar-close (and any other close path) to a cleanup
/// closure, so a window's owner runs the same teardown no matter how it closed.
/// `windowWillClose` fires for the red close button, `performClose:`, and
/// programmatic `close()` alike — the single choke point we need.
@MainActor
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

// MARK: - ASCII-only secure text field

/// `NSSecureTextField` wrapper that:
///   1. Disables marked text so Korean/Japanese/Chinese IMEs cannot swallow
///      keys for composition.
///   2. Auto-focuses and grabs first-responder once mounted, so the user can
///      start typing immediately when the window opens.
///
/// This is the third (and primary) IME-blocking layer, alongside the app-level
/// TIS swap in `PasswordWindow` and the window-level unmark in `ASCIIOnlyWindow`.
/// All three live in this file so the layered defense reads top-to-bottom.
struct ASCIISecureField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = ASCIIOnlySecureTextField(string: text)
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont(name: "Pretendard", size: 14) ?? NSFont.systemFont(ofSize: 14)
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                text.wrappedValue = field.stringValue
            }
        }
    }
}

/// NSSecureTextField that constrains its field editor to ASCII input sources
/// (Roman/Latin), so Korean/Japanese/Chinese IMEs cannot intercept alphabet
/// keys for composition. AppKit honors `allowedInputSourceLocales` on the
/// field editor's inputContext and routes keystrokes through an ABC-only
/// input source while this responder is active, regardless of the user's
/// system-wide input source choice.
private final class ASCIIOnlySecureTextField: NSSecureTextField {
    override var allowsVibrancy: Bool { false }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if let editor = currentEditor() {
            editor.inputContext?.allowedInputSourceLocales = [
                NSAllRomanInputSourcesLocaleIdentifier
            ]
            (editor as? NSTextView)?.unmarkText()
            editor.inputContext?.discardMarkedText()
            editor.inputContext?.invalidateCharacterCoordinates()
        }
        return ok
    }
}
