import Foundation
import CoreBluetooth
import Combine
import AutoLockCore

public final class BLEScanner: NSObject, ObservableObject, ProximityScanning {
    @Published public private(set) var devices: [UUID: DiscoveredDevice] = [:]
    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    @Published public private(set) var isScanning: Bool = false
    /// True once we've called `centralManagerDidUpdateState` at least once. Until
    /// then `bluetoothState == .unknown` because CoreBluetooth hasn't reported in.
    @Published public private(set) var stateResolved: Bool = false

    private var central: CBCentralManager!
    private var smoothing: [UUID: Double] = [:]
    private var pruneTimer: Timer?

    /// Supplies the current user grace period so pruning stays in sync with the
    /// proximity state machine. The pruner MUST evict later than the absence
    /// (instant-lock) point — see `LockTuning.pruneAfterSeconds` — otherwise the
    /// stale/absence lock branches in `ProximityEvaluator` become unreachable.
    /// `ProximityController` wires this to `Settings.gracePeriodSeconds`. When
    /// unset we fall back to the maximum grace so we never prune too soon.
    public var gracePeriodProvider: () -> Int = { LockTuning.maxGracePeriodSeconds }

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func startScanning() {
        guard central.state == .poweredOn else { return }
        if central.isScanning { central.stopScan() }
        // Restart so options take effect (CoreBluetooth caches the first call's options).
        central.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                // No explicit "active scan" flag exists in CoreBluetooth's public API —
                // macOS does an active scan by default when withServices is nil, so we
                // automatically receive scan responses (which is where Android nRF Connect
                // typically places the Complete Local Name).
            ]
        )
        isScanning = true
        startPruneTimer()
    }

    public func stopScanning() {
        if central.isScanning { central.stopScan() }
        isScanning = false
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    /// Evict devices silent longer than the grace-derived prune threshold,
    /// computed from the live grace period.
    func clearStale() {
        let threshold = LockTuning.pruneAfterSeconds(gracePeriodSeconds: gracePeriodProvider())
        let now = Date()
        devices = devices.filter { now.timeIntervalSince($0.value.lastSeen) <= threshold }
    }

    private func startPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: LockTuning.prunePollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.clearStale()
        }
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        stateResolved = true
        if central.state == .poweredOn {
            startScanning()
        } else {
            isScanning = false
        }
    }

    public func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        // RSSI of 127 is "unknown" per CoreBluetooth docs
        guard rssi != 127, rssi < 0 else { return }

        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        // Prefer any real name we've ever seen for this peripheral. Android nRF Connect
        // splits the name into the scan response, which arrives in a separate callback.
        let resolvedName = peripheral.name ?? advName ?? devices[id]?.name
        let displayName: String
        if let resolved = resolvedName, !resolved.isEmpty, resolved != "Unknown" {
            displayName = resolved
        } else {
            displayName = devices[id]?.name ?? "Unknown"
        }

        let prev = smoothing[id] ?? Double(rssi)
        let smoothed = prev * (1 - LockTuning.rssiSmoothingFactor) + Double(rssi) * LockTuning.rssiSmoothingFactor
        smoothing[id] = smoothed

        devices[id] = DiscoveredDevice(
            id: id,
            name: displayName,
            smoothedRssi: smoothed,
            lastSeen: Date()
        )
    }
}
