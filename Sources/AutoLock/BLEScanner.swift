import Foundation
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rssi: Int
    var smoothedRssi: Double
    var lastSeen: Date
}

final class BLEScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [UUID: DiscoveredDevice] = [:]
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isScanning: Bool = false
    /// True once we've called `centralManagerDidUpdateState` at least once. Until
    /// then `bluetoothState == .unknown` because CoreBluetooth hasn't reported in.
    @Published private(set) var stateResolved: Bool = false

    private var central: CBCentralManager!
    private var smoothing: [UUID: Double] = [:]
    private let smoothingFactor: Double = 0.3
    private var pruneTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
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

    func stopScanning() {
        if central.isScanning { central.stopScan() }
        isScanning = false
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    func currentRSSI(for id: UUID) -> Double? {
        devices[id]?.smoothedRssi
    }

    func clearStale(olderThan seconds: TimeInterval = 8) {
        let now = Date()
        devices = devices.filter { now.timeIntervalSince($0.value.lastSeen) <= seconds }
    }

    private func startPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.clearStale()
        }
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        stateResolved = true
        if central.state == .poweredOn {
            startScanning()
        } else {
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager,
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
        let smoothed = prev * (1 - smoothingFactor) + Double(rssi) * smoothingFactor
        smoothing[id] = smoothed

        devices[id] = DiscoveredDevice(
            id: id,
            name: displayName,
            rssi: rssi,
            smoothedRssi: smoothed,
            lastSeen: Date()
        )
    }
}
