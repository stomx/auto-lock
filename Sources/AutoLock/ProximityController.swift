import Foundation
import Combine
import SwiftUI

enum ProximityState: String {
    case unknown
    case near       // a tracked device is comfortably in range
    case borderline // RSSI between unlock and lock thresholds
    case away       // tracked devices missing or below lock threshold
}

/// Why we made the most recent state-machine transition. Kept as a domain
/// enum so the controller stays UI/locale-agnostic — `MenuView` decides how
/// each case is rendered to the user.
enum LockReason: Equatable {
    case signalStaleSeconds(Int)   // device hasn't advertised for N seconds
    case signalWeak                // RSSI dropped below the lock threshold
    case signalCrashed             // RSSI dropped well below threshold (instant lock)
    case deviceUnseen              // no tracked device discovered at all

    /// Stable, ASCII identifier for log lines. UI strings live in MenuView.
    var logDescription: String {
        switch self {
        case .signalStaleSeconds(let s): return "stale=\(s)s"
        case .signalWeak:                return "weak"
        case .signalCrashed:             return "crashed"
        case .deviceUnseen:              return "unseen"
        }
    }
}

/// User-facing status of the controller. Renders to a localized string in
/// the view layer so the controller doesn't carry localized text or
/// presentation timing information.
enum ControllerStatus: Equatable {
    case idle                           // toggle off
    case awaitingDevice                 // toggle on, no tracked device
    case watching                       // running, no concerns
    case countdown(reason: LockReason, secondsLeft: Int)
    case instantLock(reason: LockReason)
    case locked(reason: LockReason)
}

@MainActor
final class ProximityController: ObservableObject {
    static let shared = ProximityController()

    let scanner = BLEScanner()
    let settings = Settings.shared

    @Published private(set) var state: ProximityState = .unknown
    @Published private(set) var bestSeen: (deviceId: UUID, rssi: Double, age: TimeInterval)? = nil
    @Published private(set) var status: ControllerStatus = .idle

    private var awaySince: Date? = nil
    private var evaluationTimer: Timer? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var permissionPromptShown: Bool = false
    /// True once we've already woken the display for the current locked session.
    /// Reset whenever the screen unlocks so the next lock cycle can wake again.
    private var wakeFiredForCurrentLock: Bool = false

    private init() {
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: LockTuning.evaluationIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }

        settings.$enabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.scanner.startScanning() }
                self.status = enabled ? .watching : .idle
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
            status = .idle
            awaySince = nil
            CountdownOverlay.shared.hide()
            return
        }

        guard !settings.trackedDevices.isEmpty else {
            state = .unknown
            status = .awaitingDevice
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
        let definitiveAbsenceSeconds = Double(settings.gracePeriodSeconds) * LockTuning.absenceMultiplier

        if let best {
            let age = now.timeIntervalSince(best.lastSeen)
            bestSeen = (best.id, best.rssi, age)

            if age > definitiveAbsenceSeconds {
                lockNow(reason: .signalStaleSeconds(Int(age)))
            } else if age > Double(settings.gracePeriodSeconds) {
                handleAway(reason: .signalStaleSeconds(Int(age)))
            } else if best.rssi <= definitiveAway {
                lockNow(reason: .signalCrashed)
            } else if best.rssi >= threshold {
                state = .near
                awaySince = nil
                status = .watching
                CountdownOverlay.shared.hide()
                maybeWakeDisplay()
            } else {
                handleAway(reason: .signalWeak)
            }
        } else {
            bestSeen = nil
            handleAway(reason: .deviceUnseen)
        }
    }

    /// Skip the grace period and lock right now. Used when we're confident the
    /// user walked away (RSSI dropped well below lock threshold, or the device
    /// has been silent for far longer than the grace window).
    private func lockNow(reason: LockReason) {
        state = .away
        awaySince = nil
        status = .instantLock(reason: reason)
        CountdownOverlay.shared.hide()
        if !ScreenLocker.isScreenLocked() {
            let ok = ScreenLocker.lock()
            NSLog("AutoLock: instant lock (\(ok ? "ok" : "failed")) reason=\(reason.logDescription)")
            wakeFiredForCurrentLock = false
        }
    }

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
              best.rssi >= Double(settings.rssiThreshold) + LockTuning.wakeMarginDBm else {
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

    private func handleAway(reason: LockReason) {
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
            status = .countdown(reason: reason, secondsLeft: secondsLeft)
            // Overlay only kicks in for the final 5-second window. The overlay
            // owns its own tick once shown, so we pass the absolute deadline
            // instead of polling it from here.
            if remaining <= LockTuning.overlayWindowSeconds {
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
        status = .locked(reason: reason)
        awaySince = nil

        if !ScreenLocker.isScreenLocked() {
            let ok = ScreenLocker.lock()
            NSLog("AutoLock: lock invoked (\(ok ? "ok" : "failed")) reason=\(reason.logDescription)")
            wakeFiredForCurrentLock = false
        }
        CountdownOverlay.shared.hide()
    }
}
