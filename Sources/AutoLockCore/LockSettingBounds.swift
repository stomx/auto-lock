import Foundation

/// Valid ranges for the user-tunable lock settings, as pure clamp functions.
///
/// `Settings` clamped these only when loading from UserDefaults at init, so a
/// runtime assignment of an out-of-range value (programmatic API or a future
/// migration) would persist unclamped — e.g. `gracePeriodSeconds = 0` yields
/// near-instant locking, and an out-of-range threshold escapes the UI slider's
/// range. Centralizing the bounds here lets the `Settings` setters apply the
/// same clamp the initializer does.
public enum LockSettingBounds {
    /// Lock-threshold magnitude (positive dBm; the actual threshold is the
    /// negation). Matches the UI slider range 40...100.
    public static let thresholdMagnitudeRange: ClosedRange<Int> = 40...100

    /// Grace period (advertising-silence tolerance) in seconds. Lower bound 15;
    /// upper bound is the single source `LockTuning.maxGracePeriodSeconds`.
    public static var gracePeriodRange: ClosedRange<Int> { 15...LockTuning.maxGracePeriodSeconds }

    /// Default lock-threshold magnitude for a fresh install: -80 dBm, the
    /// centre of the README's recommended -75~-85 range, so the very first
    /// tracked device locks/unlocks sensibly without tuning. (The old default
    /// of 100 = -100 dBm almost never locked and contradicted the docs.)
    public static let defaultThresholdMagnitude = 80

    public static func clampThresholdMagnitude(_ value: Int) -> Int {
        min(thresholdMagnitudeRange.upperBound, max(thresholdMagnitudeRange.lowerBound, value))
    }

    public static func clampGracePeriodSeconds(_ value: Int) -> Int {
        let range = gracePeriodRange
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
