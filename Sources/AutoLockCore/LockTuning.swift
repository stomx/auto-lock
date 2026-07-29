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

    /// How often the BLE pruner sweeps for silent devices. Kept here (not as a
    /// bare literal in BLEScanner) because the reachability invariant — the
    /// pruner must evict only *after* the signal-loss lock decision — couples this
    /// cadence to `pruneMarginSeconds` and `evaluationIntervalSeconds`.
    public static let prunePollIntervalSeconds: TimeInterval = 2.0

    /// Self-tick interval for the countdown overlay. Decoupled from the parent
    /// 1s evaluation cadence so the digit doesn't stutter when evaluation drifts.
    public static let overlayTickIntervalSeconds: TimeInterval = 0.05

    /// How much closer (in dBm above the lock threshold) the device must be
    /// before we wake the display / attempt auto-unlock. Pure proximity-state
    /// equality is too lax — a phone in the next room can clip the threshold
    /// briefly and shouldn't light up the Mac.
    ///
    /// 20dBm 마진은 Apple Watch 처럼 송신 출력이 약한 기기에선 너무 빡빡했다.
    /// 임계값 -70 기준 발동선이 -50 이라, 손목을 키보드에 올려도 -50 을 못 넘어
    /// 자동 해제가 영영 발화하지 않는 사례가 있었다(실측 근접 ~-63). 10 으로
    /// 낮춰 발동선을 -60 으로 끌어내려 워치도 현실적으로 도달하게 한다.
    public static let wakeMarginDBm: Double = 10

    /// Drop below the lock threshold by this many dBm and we skip the
    /// countdown entirely — the user is unambiguously gone.
    public static let definitiveAwayMarginDBm: Int = 10

    /// Wait between waking the display and synthesizing the password
    /// keystrokes. WindowServer needs a moment to bring the panel up; without
    /// this, the first characters drop on the way to loginwindow.
    public static let unlockKeystrokeDelaySeconds: TimeInterval = 0.6

    /// Extra time the BLE pruner waits beyond the signal-loss lock point
    /// before evicting a silent device from the discovered map. This margin is
    /// the linchpin of the timing fix: the pruner MUST run later than the
    /// lock decision, otherwise the device disappears from the map before
    /// `evaluate()` can observe the stale `age` and finish the countdown. Set
    /// to 2 * evaluationInterval so a device is evicted only after the lock
    /// branch has had a chance to fire.
    public static let pruneMarginSeconds: TimeInterval = 2.0

    /// Total time from the last BLE advertisement to lock: first tolerate
    /// silence, then run the configured countdown.
    public static func signalLossLockPointSeconds(
        gracePeriodSeconds: Int,
        countdownSeconds: Int
    ) -> TimeInterval {
        Double(gracePeriodSeconds + countdownSeconds)
    }

    /// Timing-derived pruning threshold. Always later than the configured
    /// silence tolerance plus countdown, keeping the stale entry reachable
    /// until `ProximityEvaluator` can request the lock.
    public static func pruneAfterSeconds(
        gracePeriodSeconds: Int,
        countdownSeconds: Int
    ) -> TimeInterval {
        signalLossLockPointSeconds(
            gracePeriodSeconds: gracePeriodSeconds,
            countdownSeconds: countdownSeconds
        ) + pruneMarginSeconds
    }
}
