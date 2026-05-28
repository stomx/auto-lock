import AppKit
import SwiftUI

/// Big translucent countdown displayed in the middle of the screen during the
/// grace period. The window ignores mouse events so it never gets in the way
/// of whatever the user is doing — they can keep typing or click through it.
@MainActor
final class CountdownOverlay {
    static let shared = CountdownOverlay()

    private var window: NSPanel?
    private var label: NSTextField?
    private var tickTimer: Timer?
    private var deadline: Date?
    private var lastShown: Int = -1

    /// Show the overlay with a fixed deadline. The overlay runs its own
    /// high-frequency tick so the digit doesn't stutter when the parent
    /// evaluation cadence drifts.
    func show(until deadline: Date) {
        ensureWindow()
        self.deadline = deadline
        window?.orderFrontRegardless()
        startTicking()
        renderTick()
    }

    func hide() {
        deadline = nil
        lastShown = -1
        tickTimer?.invalidate()
        tickTimer = nil
        window?.orderOut(nil)
    }

    private func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: LockTuning.overlayTickIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderTick() }
        }
        // .common lets the timer fire during UI tracking (menu open, drag, etc.)
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func renderTick() {
        guard let deadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            // Skip rendering "0" — the parent locks the screen at this point
            // and the overlay should disappear, not flash a final digit.
            return
        }
        let secondsLeft = Int(ceil(remaining))
        if secondsLeft != lastShown {
            label?.stringValue = "\(secondsLeft)"
            lastShown = secondsLeft
        }
    }

    private func ensureWindow() {
        if window != nil { return }

        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Square box whose side equals half of the screen height.
        let side = screen.height / 2
        let size = NSSize(width: side, height: side)
        let origin = NSPoint(
            x: screen.midX - side / 2,
            y: screen.midY - side / 2
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        // Font size scaled to the box. Cap height factor leaves room so a single
        // digit fits comfortably with built-in padding.
        let fontSize: CGFloat = side * 0.7
        let font = NSFont(name: "Pretendard-Bold", size: fontSize)
            ?? NSFont(name: "Pretendard", size: fontSize)
            ?? .monospacedDigitSystemFont(ofSize: fontSize, weight: .heavy)

        let textField = NSTextField(labelWithString: "")
        textField.font = font
        textField.textColor = .white
        textField.alignment = .center
        textField.isBezeled = false
        textField.isEditable = false
        textField.drawsBackground = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.wantsLayer = true
        textField.layer?.shadowColor = NSColor.black.cgColor
        textField.layer?.shadowOpacity = 0.6
        textField.layer?.shadowRadius = 12
        textField.layer?.shadowOffset = .zero

        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        host.layer?.cornerRadius = side * 0.12
        host.addSubview(textField)

        // NSTextField centers horizontally via .alignment, but vertical centering
        // leaves an ascender-heavy offset; nudging down by ~8% lands the digit
        // visually in the middle.
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: host.centerYAnchor, constant: fontSize * 0.08),
            textField.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor),
        ])

        panel.contentView = host
        window = panel
        label = textField
    }
}
