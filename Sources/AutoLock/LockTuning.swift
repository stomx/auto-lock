import Foundation

/// Domain tuning constants. Centralized so behavior changes are reviewable in
/// one place instead of buried as numeric literals across files. UI design
/// tokens (colors, font sizes, opacities) intentionally live elsewhere — this
/// file is for the proximity / locking state machine only.
enum LockTuning {
    /// How often `ProximityController.evaluate()` re-checks signal vs. threshold.
    static let evaluationIntervalSeconds: TimeInterval = 1.0

    /// EWMA blend for incoming RSSI samples: `new * factor + prev * (1 - factor)`.
    /// Higher = more responsive but jitterier; lower = smoother but laggier.
    static let rssiSmoothingFactor: Double = 0.3

    /// Multiplier on the user-configured grace period that defines "definitely
    /// absent". If the device hasn't been seen for grace * this, we lock
    /// immediately rather than running the countdown again.
    static let absenceMultiplier: Double = 2.0

    /// Final-stretch window where the on-screen countdown overlay actually
    /// renders. The grace period itself can be much longer; the overlay only
    /// announces the last few seconds.
    static let overlayWindowSeconds: TimeInterval = 5

    /// Self-tick interval for the countdown overlay. Decoupled from the parent
    /// 1s evaluation cadence so the digit doesn't stutter when evaluation drifts.
    static let overlayTickIntervalSeconds: TimeInterval = 0.05

    /// How much closer (in dBm above the lock threshold) the device must be
    /// before we wake the display / attempt auto-unlock. Pure proximity-state
    /// equality is too lax — a phone in the next room can clip the threshold
    /// briefly and shouldn't light up the Mac.
    static let wakeMarginDBm: Double = 20

    /// Drop below the lock threshold by this many dBm and we skip the
    /// countdown entirely — the user is unambiguously gone.
    static let definitiveAwayMarginDBm: Int = 10

    /// Wait between waking the display and synthesizing the password
    /// keystrokes. WindowServer needs a moment to bring the panel up; without
    /// this, the first characters drop on the way to loginwindow.
    static let unlockKeystrokeDelaySeconds: TimeInterval = 0.6
}
