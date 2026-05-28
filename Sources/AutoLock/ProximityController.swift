import Foundation
import Combine
import SwiftUI

enum ProximityState: String {
    case unknown
    case near       // a tracked device is comfortably in range
    case borderline // RSSI between unlock and lock thresholds
    case away       // tracked devices missing or below lock threshold
}

@MainActor
final class ProximityController: ObservableObject {
    static let shared = ProximityController()

    let scanner = BLEScanner()
    let settings = Settings.shared

    @Published private(set) var state: ProximityState = .unknown
    @Published private(set) var bestSeen: (deviceId: UUID, rssi: Double, age: TimeInterval)? = nil
    @Published private(set) var statusMessage: String = "대기 중"

    private var awaySince: Date? = nil
    private var evaluationTimer: Timer? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var permissionPromptShown: Bool = false
    /// True once we've already woken the display for the current locked session.
    /// Reset whenever the screen unlocks so the next lock cycle can wake again.
    private var wakeFiredForCurrentLock: Bool = false

    private init() {
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }

        settings.$enabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.scanner.startScanning() }
                self.statusMessage = enabled ? "감시 활성화됨" : "비활성화됨"
            }
            .store(in: &cancellables)

        // Once CoreBluetooth reports its first state, surface a guidance dialog
        // if the user hasn't granted permission. We only show this once per launch
        // so the user isn't pestered while they're navigating to Settings.
        scanner.$stateResolved
            .combineLatest(scanner.$bluetoothState)
            .sink { [weak self] resolved, state in
                guard let self, resolved, !self.permissionPromptShown else { return }
                if state == .unauthorized || state == .poweredOff || state == .unsupported {
                    self.permissionPromptShown = true
                    PermissionPrompt.presentIfNeeded(state: state)
                }
            }
            .store(in: &cancellables)
    }

    var menuBarIcon: String {
        guard settings.enabled else { return "lock.open.fill" }
        switch state {
        case .near: return "lock.open.fill"
        case .borderline: return "lock.rotation"
        case .away: return "lock.fill"
        case .unknown: return "lock.slash"
        }
    }

    func evaluate() {
        guard settings.enabled else {
            state = .unknown
            statusMessage = "비활성화됨"
            awaySince = nil
            CountdownOverlay.shared.hide()
            return
        }

        guard !settings.trackedDevices.isEmpty else {
            state = .unknown
            statusMessage = "등록된 디바이스 없음"
            awaySince = nil
            CountdownOverlay.shared.hide()
            return
        }

        var best: (id: UUID, rssi: Double, lastSeen: Date)? = nil
        for tracked in settings.trackedDevices {
            if let device = scanner.devices[tracked.id] {
                if best == nil || device.smoothedRssi > best!.rssi {
                    best = (tracked.id, device.smoothedRssi, device.lastSeen)
                }
            }
        }

        let now = Date()
        let threshold = Double(settings.rssiThreshold)
        let definitiveAway = Double(settings.definitiveAwayThreshold)
        let definitiveAbsenceSeconds = Double(settings.gracePeriodSeconds * 2)

        if let best {
            let age = now.timeIntervalSince(best.lastSeen)
            bestSeen = (best.id, best.rssi, age)

            if age > definitiveAbsenceSeconds {
                lockNow(reason: "신호 장기 끊김 \(Int(age))s")
            } else if age > Double(settings.gracePeriodSeconds) {
                handleAway(reason: "신호 끊김 \(Int(age))s")
            } else if best.rssi <= definitiveAway {
                lockNow(reason: "신호 급락")
            } else if best.rssi >= threshold {
                state = .near
                awaySince = nil
                statusMessage = ""
                CountdownOverlay.shared.hide()
                maybeWakeDisplay()
            } else {
                handleAway(reason: "신호 약함")
            }
        } else {
            bestSeen = nil
            handleAway(reason: "디바이스 미감지")
        }
    }

    /// Skip the grace period and lock right now. Used when we're confident the
    /// user walked away (RSSI dropped well below lock threshold, or the device
    /// has been silent for far longer than the grace window).
    private func lockNow(reason: String) {
        state = .away
        awaySince = nil
        statusMessage = "즉시 잠금: \(reason)"
        CountdownOverlay.shared.hide()
        if !ScreenLocker.isScreenLocked() {
            let ok = ScreenLocker.lock()
            NSLog("AutoLock: instant lock (\(ok ? "ok" : "failed")) reason=\(reason)")
            wakeFiredForCurrentLock = false
        }
    }

    /// Margin (dBm, positive) that the live RSSI must beat over the lock
    /// threshold before we wake / auto-unlock. Locking can be liberal — false
    /// locks are recoverable. Waking should be conservative: a brief RSSI
    /// spike from a phone in the next room shouldn't light up the Mac.
    private let wakeMarginDBm: Double = 20

    /// If the screen is currently locked and the user hasn't been re-detected
    /// yet for this lock session, light up the display so the auth prompt
    /// (Touch ID / password / Apple Watch) is already visible. When the
    /// `autoUnlock` toggle is on we go one step further and post the saved
    /// password to loginwindow. Either way we only fire once per lock session
    /// so we don't hammer the APIs while the user is still nearby.
    private func maybeWakeDisplay() {
        guard settings.wakeOnProximity else { return }
        guard !wakeFiredForCurrentLock else { return }
        guard ScreenLocker.isScreenLocked() else {
            // User unlocked — arm wake for the next lock cycle.
            wakeFiredForCurrentLock = false
            return
        }
        // Require RSSI well above the lock threshold (i.e. genuinely close)
        // before triggering. `state == .near` alone is too lax — its threshold
        // matches the lock decision, so the user could be at the edge.
        guard let best = bestSeen,
              best.rssi >= Double(settings.rssiThreshold) + wakeMarginDBm else {
            return
        }

        if settings.autoUnlock {
            let result = UnlockTrigger.attempt()
            NSLog("AutoLock: auto-unlock attempt result=\(result)")
            wakeFiredForCurrentLock = true
            return
        }

        let ok = DisplayWaker.wake()
        NSLog("AutoLock: proximity wake (\(ok ? "ok" : "failed"))")
        wakeFiredForCurrentLock = true
    }

    private func handleAway(reason: String) {
        if awaySince == nil {
            awaySince = Date()
        }
        let startedAt = awaySince ?? Date()
        let grace = Double(settings.gracePeriodSeconds)
        let deadline = startedAt.addingTimeInterval(grace)
        let remaining = deadline.timeIntervalSinceNow

        if remaining > 0 {
            state = .borderline
            let secondsLeft = Int(ceil(remaining))
            statusMessage = "\(reason) — \(secondsLeft)s 후 잠금"
            // Overlay only kicks in for the final 5-second window. The overlay
            // owns its own tick once shown, so we pass the absolute deadline
            // instead of polling it from here.
            if remaining <= 5 {
                CountdownOverlay.shared.show(until: deadline)
            } else {
                CountdownOverlay.shared.hide()
            }
            return
        }

        // Grace expired. Lock immediately and dismiss the overlay — the
        // overlay's tick stops rendering once remaining <= 0 so no "0"
        // frame flashes. awaySince resets so the next out-of-range cycle
        // starts fresh from the top of the grace window.
        state = .away
        statusMessage = "잠금: \(reason)"
        awaySince = nil

        if !ScreenLocker.isScreenLocked() {
            let ok = ScreenLocker.lock()
            NSLog("AutoLock: lock invoked (\(ok ? "ok" : "failed")) reason=\(reason)")
            wakeFiredForCurrentLock = false
        }
        CountdownOverlay.shared.hide()
    }
}
