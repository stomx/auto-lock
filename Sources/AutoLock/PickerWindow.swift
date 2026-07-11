import AppKit
import SwiftUI
import AutoLockKit

/// Standalone NSWindow for the device picker.
///
/// `MenuBarExtra(.window)` + `.sheet` is unreliable: the popover loses focus on
/// any outside click and the sheet binding can get stuck in a half-open state
/// where the dialog refuses to dismiss. Hosting the picker in its own window
/// sidesteps the popover lifecycle entirely.
@MainActor
enum PickerWindow {
    private static var window: NSWindow?
    private static weak var scanner: BLEScanner?
    private static let closeDelegate = WindowCloseDelegate { cleanup() }

    static func show(scanner: BLEScanner, settings: AutoLockKit.Settings) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "디바이스 선택"
        win.center()
        win.isReleasedWhenClosed = false
        // Titlebar close must clear the static window reference too, otherwise
        // re-opening returns a stale orderOut window. (PasswordWindow shares
        // this delegate type.)
        win.delegate = closeDelegate
        win.contentView = NSHostingView(
            rootView: DevicePickerView(
                scanner: scanner,
                settings: settings,
                onClose: { close() }
            )
        )
        self.scanner = scanner
        scanner.startScanning(for: .deviceSelection)
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        window?.close()
    }

    private static func cleanup() {
        scanner?.stopScanning(for: .deviceSelection)
        scanner = nil
        window = nil
    }
}
