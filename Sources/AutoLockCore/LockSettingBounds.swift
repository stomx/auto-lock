import Foundation

/// Valid ranges and defaults for the user-tunable lock settings.
///
/// Centralizing normalization here keeps the UI, persisted values, and runtime
/// assignments on the same contract.
public enum LockSettingBounds {
    /// Lock-threshold magnitude (positive dBm; the actual threshold is the
    /// negation). Matches the UI slider range 40...100 in 5 dBm increments.
    public static let thresholdMagnitudeRange: ClosedRange<Int> = 40...100
    public static let thresholdMagnitudeStep = 5

    /// Default lock-threshold magnitude for a fresh install: -80 dBm, the
    /// centre of the README's recommended -75~-85 range, so the very first
    /// tracked device locks/unlocks sensibly without tuning. (The old default
    /// of 100 = -100 dBm almost never locked and contradicted the docs.)
    public static let defaultThresholdMagnitude = 80

    /// How long a missing BLE advertisement is tolerated before the visible
    /// lock countdown starts.
    public static let gracePeriodRange: ClosedRange<Int> = 5...60
    public static let gracePeriodStep = 5
    public static let defaultGracePeriodSeconds = 10

    /// Duration of the lock countdown once an away condition is confirmed.
    public static let countdownRange: ClosedRange<Int> = 1...30
    public static let countdownStep = 1
    public static let defaultCountdownSeconds = 5

    public static func clampThresholdMagnitude(_ value: Int) -> Int {
        let clamped = min(thresholdMagnitudeRange.upperBound, max(thresholdMagnitudeRange.lowerBound, value))
        let offset = clamped - thresholdMagnitudeRange.lowerBound
        let snapped = ((offset + thresholdMagnitudeStep / 2) / thresholdMagnitudeStep) * thresholdMagnitudeStep
        return thresholdMagnitudeRange.lowerBound + snapped
    }

    public static func clampGracePeriodSeconds(_ value: Int) -> Int {
        let clamped = min(gracePeriodRange.upperBound, max(gracePeriodRange.lowerBound, value))
        let offset = clamped - gracePeriodRange.lowerBound
        let snapped = ((offset + gracePeriodStep / 2) / gracePeriodStep) * gracePeriodStep
        return gracePeriodRange.lowerBound + snapped
    }

    public static func clampCountdownSeconds(_ value: Int) -> Int {
        min(countdownRange.upperBound, max(countdownRange.lowerBound, value))
    }
}
