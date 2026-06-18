import Testing
import Foundation
@testable import AutoLockCore

/// `ScanPolicy.shouldScan` decides whether the BLE scanner should be actively
/// scanning, from two facts: whether scanning was *requested* (the feature is
/// on / a diagnostic asked for it) and whether Bluetooth is powered on.
///
/// Fixes a defect where `BLEScanner.centralManagerDidUpdateState` called
/// `startScanning()` unconditionally on `.poweredOn`, so the scanner could
/// resume even while AutoLock was toggled OFF — defeating the battery/privacy
/// intent of the off switch. Gating auto-resume on `requested` closes that.
@Suite struct ScanPolicyTests {

    // 1. 요청됨 + BT 켜짐 → 스캔.
    @Test func requestedAndPoweredScans() {
        #expect(ScanPolicy.shouldScan(requested: true, poweredOn: true) == true)
    }

    // 2. 요청 안 됨 + BT 켜짐 → 스캔 안 함 (OFF인데 .poweredOn 콜백으로 재개되던 버그).
    @Test func notRequestedDoesNotScanEvenWhenPowered() {
        #expect(ScanPolicy.shouldScan(requested: false, poweredOn: true) == false)
    }

    // 3. 요청됨 + BT 꺼짐 → 스캔 불가.
    @Test func requestedButPoweredOffCannotScan() {
        #expect(ScanPolicy.shouldScan(requested: true, poweredOn: false) == false)
    }

    // 4. 요청 안 됨 + BT 꺼짐 → 스캔 안 함.
    @Test func notRequestedPoweredOffDoesNotScan() {
        #expect(ScanPolicy.shouldScan(requested: false, poweredOn: false) == false)
    }
}
