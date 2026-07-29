import Foundation

/// Immutable input to a single proximity evaluation. Everything the decision
/// depends on is captured here so `ProximityEvaluator.decide` can stay a pure
/// function — no clock reads, no I/O, no CoreBluetooth. The controller builds
/// one of these each tick from live scanner/settings state.
public struct ProximitySnapshot {
    public let now: Date
    public let best: BestDevice?            // strongest tracked device, or nil if none visible
    public let rssiThreshold: Int           // lock threshold (negative dBm)
    public let definitiveAwayThreshold: Int // crash threshold (further below)
    public let gracePeriodSeconds: Int      // advertising-silence tolerance
    public let countdownSeconds: Int        // visible countdown after away confirmation
    public let awaySince: Date?             // start of the current away cycle, if any

    public struct BestDevice: Equatable {
        public let id: UUID
        public let smoothedRssi: Double
        public let lastSeen: Date

        public init(id: UUID, smoothedRssi: Double, lastSeen: Date) {
            self.id = id
            self.smoothedRssi = smoothedRssi
            self.lastSeen = lastSeen
        }
    }

    public init(now: Date,
                best: BestDevice?,
                rssiThreshold: Int,
                definitiveAwayThreshold: Int,
                gracePeriodSeconds: Int,
                countdownSeconds: Int,
                awaySince: Date?) {
        self.now = now
        self.best = best
        self.rssiThreshold = rssiThreshold
        self.definitiveAwayThreshold = definitiveAwayThreshold
        self.gracePeriodSeconds = gracePeriodSeconds
        self.countdownSeconds = countdownSeconds
        self.awaySince = awaySince
    }
}

/// The outcome of one evaluation: the new published state/status, the
/// side-effect the controller should perform, and the away-cycle start to
/// write back. Pure value — the controller owns the actual side effects.
public struct ProximityDecision: Equatable {
    public let state: ProximityState
    public let status: ControllerStatus
    public let action: Action
    public let awaySince: Date?

    /// Side-effect instruction. `.lock` implies the overlay should be hidden.
    public enum Action: Equatable {
        case watching                   // near — controller hides overlay + maybeWakeDisplay
        case showOverlay(until: Date)   // configured countdown is active
        case hideOverlay                // still inside signal-loss tolerance
        case lock(reason: LockReason)   // lock the screen now (also hides overlay)
    }

    public init(state: ProximityState, status: ControllerStatus, action: Action, awaySince: Date?) {
        self.state = state
        self.status = status
        self.action = action
        self.awaySince = awaySince
    }
}

/// Pure proximity/locking decision logic, extracted from
/// `ProximityController.evaluate()` so it can be unit tested without a host
/// app, CoreBluetooth, or a running clock. Callers supply both guards
/// (toggle off / no tracked device) before reaching here; this function
/// assumes the feature is enabled and at least one device is tracked.
public enum ProximityEvaluator {
    public static func decide(_ s: ProximitySnapshot) -> ProximityDecision {
        let grace = Double(s.gracePeriodSeconds)
        let countdown = Double(s.countdownSeconds)

        guard let best = s.best else {
            let cycleStartedAt = s.awaySince ?? s.now
            return away(
                reason: .deviceUnseen,
                snapshot: s,
                cycleStartedAt: cycleStartedAt,
                countdownStartedAt: cycleStartedAt.addingTimeInterval(grace),
                countdown: countdown
            )
        }

        let age = s.now.timeIntervalSince(best.lastSeen)

        if age >= grace {
            // The device has been silent for the configured tolerance. Anchor
            // the countdown to lastSeen + grace so a 10s tolerance plus a 5s
            // countdown locks at 15s, without adding an evaluation-tick delay.
            let cycleStartedAt = s.awaySince ?? best.lastSeen
            return away(
                reason: .signalStaleSeconds(Int(age)),
                snapshot: s,
                cycleStartedAt: cycleStartedAt,
                countdownStartedAt: best.lastSeen.addingTimeInterval(grace),
                countdown: countdown
            )
        } else if best.smoothedRssi <= Double(s.definitiveAwayThreshold) {
            // RSSI crashed well below the lock threshold — user is gone.
            return instantLock(reason: .signalCrashed)
        } else if best.smoothedRssi >= Double(s.rssiThreshold) {
            // Comfortably in range.
            return ProximityDecision(state: .near, status: .watching, action: .watching, awaySince: nil)
        } else {
            // Between unlock and lock thresholds — weak signal, start countdown.
            let cycleStartedAt = s.awaySince ?? s.now
            return away(
                reason: .signalWeak,
                snapshot: s,
                cycleStartedAt: cycleStartedAt,
                countdownStartedAt: cycleStartedAt,
                countdown: countdown
            )
        }
    }

    private static func instantLock(reason: LockReason) -> ProximityDecision {
        ProximityDecision(state: .away, status: .instantLock(reason: reason), action: .lock(reason: reason), awaySince: nil)
    }

    /// Returns a waiting/countdown decision until the configured deadline, then
    /// locks. The overlay appears only after `countdownStartedAt`; this keeps the
    /// silent-signal tolerance quiet and shows the complete configured countdown.
    private static func away(
        reason: LockReason,
        snapshot s: ProximitySnapshot,
        cycleStartedAt: Date,
        countdownStartedAt: Date,
        countdown: Double
    ) -> ProximityDecision {
        let deadline = countdownStartedAt.addingTimeInterval(countdown)
        let remaining = deadline.timeIntervalSince(s.now)

        if remaining > 0 {
            let secondsLeft = Int(ceil(remaining))
            let action: ProximityDecision.Action = s.now >= countdownStartedAt
                ? .showOverlay(until: deadline)
                : .hideOverlay
            return ProximityDecision(
                state: .borderline,
                status: .countdown(reason: reason, secondsLeft: secondsLeft),
                action: action,
                awaySince: cycleStartedAt
            )
        }

        // Countdown expired — lock. awaySince resets so the next cycle starts fresh.
        return ProximityDecision(state: .away, status: .locked(reason: reason), action: .lock(reason: reason), awaySince: nil)
    }
}
