import Foundation

/// Domain tuning constants. Centralized so behavior changes are reviewable in
/// one place instead of buried as numeric literals across files. UI design
/// tokens (colors, font sizes, opacities) intentionally live elsewhere — this
/// file is for the proximity / locking state machine only.
public enum LockTuning {
    /// How often `ProximityController.evaluate()` re-checks signal vs. threshold.
    public static let evaluationIntervalSeconds: TimeInterval = 1.0

    /// EWMA blend for incoming RSSI samples: `new * factor + prev * (1 - factor)`.
    /// Higher = more responsive but jitterier; lower = smoother but laggier.
    public static let rssiSmoothingFactor: Double = 0.3

    /// Multiplier on the user-configured grace period that defines "definitely
    /// absent". If the device hasn't been seen for grace * this, we lock
    /// immediately rather than running the countdown again.
    public static let absenceMultiplier: Double = 2.0

    /// Advertising-silence tolerance before the away countdown starts, in
    /// seconds. Previously a user-tunable slider (15–60s); now a fixed product
    /// constant — 15s balances "don't lock on a brief BLE dropout" against
    /// "don't leave the Mac open too long after you walk away". The Settings
    /// plumbing still threads this value through, but the UI no longer exposes
    /// a control and `Settings.gracePeriodSeconds` always returns this.
    public static let fixedGracePeriodSeconds: Int = 15

    /// Historical upper bound of the (now removed) user-configurable grace
    /// period. Retained only as the BLE pruner's fail-safe default for when no
    /// provider is wired, so it never prunes too soon.
    public static let maxGracePeriodSeconds: Int = 60

    /// How often the BLE pruner sweeps for silent devices. Kept here (not as a
    /// bare literal in BLEScanner) because the reachability invariant — the
    /// pruner must evict only *after* the absence decision — couples this
    /// cadence to `pruneMarginSeconds` and `evaluationIntervalSeconds`.
    public static let prunePollIntervalSeconds: TimeInterval = 2.0

    /// Final-stretch window where the on-screen countdown overlay actually
    /// renders. The grace period itself can be much longer; the overlay only
    /// announces the last few seconds.
    public static let overlayWindowSeconds: TimeInterval = 5

    /// Self-tick interval for the countdown overlay. Decoupled from the parent
    /// 1s evaluation cadence so the digit doesn't stutter when evaluation drifts.
    public static let overlayTickIntervalSeconds: TimeInterval = 0.05

    /// How much closer (in dBm above the lock threshold) the device must be
    /// before we wake the display / attempt auto-unlock. Pure proximity-state
    /// equality is too lax — a phone in the next room can clip the threshold
    /// briefly and shouldn't light up the Mac.
    public static let wakeMarginDBm: Double = 20

    /// Drop below the lock threshold by this many dBm and we skip the
    /// countdown entirely — the user is unambiguously gone.
    public static let definitiveAwayMarginDBm: Int = 10

    /// Wait between waking the display and synthesizing the password
    /// keystrokes. WindowServer needs a moment to bring the panel up; without
    /// this, the first characters drop on the way to loginwindow.
    public static let unlockKeystrokeDelaySeconds: TimeInterval = 0.6

    /// Extra time the BLE pruner waits beyond the absence (instant-lock) point
    /// before evicting a silent device from the discovered map. This margin is
    /// the linchpin of the timing fix: the pruner MUST run later than the
    /// absence decision, otherwise the device disappears from the map before
    /// `evaluate()` can ever observe a stale `age` — and the stale/absence lock
    /// branches become dead code. Set to 2 * evaluationInterval so a device is
    /// evicted only after the instant-lock branch has had a chance to fire.
    public static let pruneMarginSeconds: TimeInterval = 2.0

    /// The "definitely absent" point: how long a device may stay silent before
    /// `ProximityEvaluator` skips the countdown and locks instantly. The single
    /// definition of `grace * absenceMultiplier`, shared by the evaluator, the
    /// pruning threshold, and the reachability test so they can never drift.
    public static func absencePointSeconds(gracePeriodSeconds: Int) -> TimeInterval {
        Double(gracePeriodSeconds) * absenceMultiplier
    }

    /// Grace-derived pruning threshold. `BLEScanner.clearStale` evicts devices
    /// silent for longer than this. Always greater than the absence point by
    /// `pruneMarginSeconds`, guaranteeing the stale-countdown (age > grace) and
    /// instant-lock (age > absence point) branches in `ProximityEvaluator` are
    /// reachable.
    public static func pruneAfterSeconds(gracePeriodSeconds: Int) -> TimeInterval {
        absencePointSeconds(gracePeriodSeconds: gracePeriodSeconds) + pruneMarginSeconds
    }
}
