import Foundation

/// Pure policy for whether the BLE scanner should be actively scanning.
///
/// `BLEScanner.centralManagerDidUpdateState` previously called
/// `startScanning()` unconditionally whenever Bluetooth reported `.poweredOn`,
/// so the scanner could silently resume even while AutoLock was toggled OFF —
/// burning battery and scanning in the background against the user's intent.
/// Gating auto-resume on an explicit `requested` flag (set by `startScanning`,
/// cleared by `stopScanning`) restores "off means off".
///
/// Takes `poweredOn: Bool` rather than `CBManagerState` so the domain layer
/// stays Foundation-only; the scanner maps its CoreBluetooth state in.
public enum ScanPolicy {
    public static func shouldScan(requested: Bool, poweredOn: Bool) -> Bool {
        requested && poweredOn
    }
}
