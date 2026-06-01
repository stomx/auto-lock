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
    public let gracePeriodSeconds: Int
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
                awaySince: Date?) {
        self.now = now
        self.best = best
        self.rssiThreshold = rssiThreshold
        self.definitiveAwayThreshold = definitiveAwayThreshold
        self.gracePeriodSeconds = gracePeriodSeconds
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
        case showOverlay(until: Date)   // final grace window — show countdown
        case hideOverlay                // borderline but outside overlay window
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
        let absenceSeconds = LockTuning.absencePointSeconds(gracePeriodSeconds: s.gracePeriodSeconds)

        guard let best = s.best else {
            return away(reason: .deviceUnseen, snapshot: s, grace: grace)
        }

        let age = s.now.timeIntervalSince(best.lastSeen)

        if age > absenceSeconds {
            // Silent far longer than the grace window — lock instantly.
            return instantLock(reason: .signalStaleSeconds(Int(age)))
        } else if age > grace {
            // Silent past the grace window — run the away countdown.
            return away(reason: .signalStaleSeconds(Int(age)), snapshot: s, grace: grace)
        } else if best.smoothedRssi <= Double(s.definitiveAwayThreshold) {
            // RSSI crashed well below the lock threshold — user is gone.
            return instantLock(reason: .signalCrashed)
        } else if best.smoothedRssi >= Double(s.rssiThreshold) {
            // Comfortably in range.
            return ProximityDecision(state: .near, status: .watching, action: .watching, awaySince: nil)
        } else {
            // Between unlock and lock thresholds — weak signal, start countdown.
            return away(reason: .signalWeak, snapshot: s, grace: grace)
        }
    }

    private static func instantLock(reason: LockReason) -> ProximityDecision {
        ProximityDecision(state: .away, status: .instantLock(reason: reason), action: .lock(reason: reason), awaySince: nil)
    }

    /// Grace-period countdown. Returns a countdown (with overlay in the final
    /// window) while time remains, or a lock once the grace deadline passes.
    private static func away(reason: LockReason, snapshot s: ProximitySnapshot, grace: Double) -> ProximityDecision {
        let startedAt = s.awaySince ?? s.now
        let deadline = startedAt.addingTimeInterval(grace)
        let remaining = deadline.timeIntervalSince(s.now)

        if remaining > 0 {
            let secondsLeft = Int(ceil(remaining))
            let action: ProximityDecision.Action = remaining <= LockTuning.overlayWindowSeconds
                ? .showOverlay(until: deadline)
                : .hideOverlay
            return ProximityDecision(
                state: .borderline,
                status: .countdown(reason: reason, secondsLeft: secondsLeft),
                action: action,
                awaySince: startedAt
            )
        }

        // Grace expired — lock. awaySince resets so the next cycle starts fresh.
        return ProximityDecision(state: .away, status: .locked(reason: reason), action: .lock(reason: reason), awaySince: nil)
    }
}
