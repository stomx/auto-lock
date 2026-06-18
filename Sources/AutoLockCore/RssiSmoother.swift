import Foundation

/// Exponentially-weighted moving average of raw RSSI samples, kept per device.
///
/// Extracted from `BLEScanner` so the smoothing math is unit-testable without
/// CoreBluetooth, and — more importantly — so the per-device EWMA state can be
/// pruned in lockstep with the discovered-device map. Previously the scanner
/// evicted silent devices from its `devices` map but left their smoothing
/// entries behind, so the dictionary grew unbounded as Apple devices rotated
/// their BLE identifiers. `prune(keeping:)` closes that leak.
public struct RssiSmoother {
    private var state: [UUID: Double] = [:]

    public init() {}

    /// Number of devices currently holding smoothing state. Exposed for tests
    /// and diagnostics; the leak fix is observable through this count.
    public var trackedCount: Int { state.count }

    /// Blend a new raw sample into the device's running average and return the
    /// smoothed value. The first sample for a device is returned unchanged
    /// (there is no prior state to blend against).
    public mutating func update(id: UUID, rawRssi: Int) -> Double {
        let raw = Double(rawRssi)
        let prev = state[id] ?? raw
        let smoothed = prev * (1 - LockTuning.rssiSmoothingFactor) + raw * LockTuning.rssiSmoothingFactor
        state[id] = smoothed
        return smoothed
    }

    /// Drop smoothing state for any device not in `keeping`. Call this whenever
    /// the scanner prunes its discovered-device map so the two stay in sync and
    /// the EWMA dictionary can't grow without bound.
    public mutating func prune(keeping ids: Set<UUID>) {
        state = state.filter { ids.contains($0.key) }
    }
}
