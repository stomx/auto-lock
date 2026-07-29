import Foundation
import CoreBluetooth
import Combine
import AutoLockCore

@MainActor
public final class BLEScanner: NSObject, ObservableObject, ProximityScanning {
    @Published public private(set) var devices: [UUID: DiscoveredDevice] = [:]
    /// The adapter state as a pure domain enum — the CoreBluetooth
    /// `CBManagerState` is mapped here and never crosses this boundary, so UI /
    /// diagnostics / permission code depend on `AutoLockCore`, not CoreBluetooth.
    @Published public private(set) var bluetoothState: BluetoothPowerState = .unknown
    @Published public private(set) var isScanning: Bool = false
    /// True once we've called `centralManagerDidUpdateState` at least once. Until
    /// then `bluetoothState == .unknown` because CoreBluetooth hasn't reported in.
    @Published public private(set) var stateResolved: Bool = false

    private var central: CBCentralManager!
    private var smoother = RssiSmoother()
    private var pruneTimer: Timer?
    /// Scan requests are tracked per purpose so closing the device picker cannot
    /// cancel proximity monitoring (and pairing can scan while monitoring is off).
    private var scanDemand = ScanDemand()

    /// Supplies the current signal-loss tolerance and countdown so pruning stays
    /// in sync with the proximity state machine. The pruner MUST evict later
    /// than tolerance + countdown — see `LockTuning.pruneAfterSeconds`.
    /// Safe maximum fallbacks ensure an unwired scanner never prunes too soon.
    public var gracePeriodProvider: @MainActor () -> Int = {
        LockSettingBounds.gracePeriodRange.upperBound
    }
    public var countdownPeriodProvider: @MainActor () -> Int = {
        LockSettingBounds.countdownRange.upperBound
    }

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func startScanning() {
        startScanning(for: .proximityMonitoring)
    }

    public func startScanning(for purpose: ScanPurpose) {
        // Record the request even if Bluetooth isn't ready yet, so the
        // poweredOn callback can resume scanning later.
        let wasRequested = scanDemand.isRequested
        scanDemand.request(purpose)
        AppLog.record(
            .bluetooth,
            code: "scan_demand_added",
            outcome: .observed,
            message: "블루투스 스캔 요청이 추가됨",
            metadata: [
                "purpose": String(describing: purpose),
                "shared_scan_already_requested": String(wasRequested)
            ]
        )
        ensureScanning()
    }

    private func ensureScanning() {
        guard scanDemand.isRequested else { return }
        guard central.state == .poweredOn else { return }
        // A second purpose may join an existing scan. Do not restart CoreBluetooth
        // in that case; both clients consume the same discovery stream.
        guard !central.isScanning else {
            isScanning = true
            return
        }
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
        AppLog.record(
            .bluetooth,
            code: "ble_scan_started",
            outcome: .success,
            message: "CoreBluetooth 스캔 시작",
            metadata: ["state": bluetoothState.logDescription]
        )
        startPruneTimer()
    }

    public func stopScanning() {
        stopScanning(for: .proximityMonitoring)
    }

    public func stopScanning(for purpose: ScanPurpose) {
        scanDemand.cancel(purpose)
        // Another client (for example the picker) still needs the shared scan.
        guard !scanDemand.isRequested else {
            AppLog.record(
                .bluetooth,
                code: "scan_demand_removed",
                outcome: .skipped,
                message: "다른 사용 목적이 남아 블루투스 스캔을 유지함",
                metadata: ["purpose": String(describing: purpose)]
            )
            return
        }
        if central.isScanning { central.stopScan() }
        isScanning = false
        pruneTimer?.invalidate()
        pruneTimer = nil
        // Drop discovered devices and their smoothing state. Pruning is paused
        // while stopped, so without this a long-disabled scanner would keep
        // stale `lastSeen` entries; on re-enable the first evaluate() could see
        // an age past the configured lock point before any fresh advertisement
        // arrives.
        devices = [:]
        smoother.prune(keeping: [])
        AppLog.record(
            .bluetooth,
            code: "ble_scan_stopped",
            outcome: .success,
            message: "모든 요청이 해제되어 CoreBluetooth 스캔 중지",
            metadata: ["purpose": String(describing: purpose)]
        )
    }

    /// Evict devices only after the live tolerance + countdown lock point.
    /// The smoother is pruned in lockstep so a rotated/departed device leaves
    /// no EWMA state behind.
    func clearStale() {
        let threshold = LockTuning.pruneAfterSeconds(
            gracePeriodSeconds: gracePeriodProvider(),
            countdownSeconds: countdownPeriodProvider()
        )
        let now = MonotonicClock.now()
        devices = devices.filter { now.timeIntervalSince($0.value.lastSeen) <= threshold }
        smoother.prune(keeping: Set(devices.keys))
    }

    private func startPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: LockTuning.prunePollIntervalSeconds, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so this fires on the main thread;
            // assert that to the compiler to reach the main-actor `clearStale`.
            MainActor.assumeIsolated { self?.clearStale() }
        }
    }
}

// CoreBluetooth invokes these delegate methods on the queue we passed to
// `CBCentralManager(delegate:queue:)` — `.main` — so they are already on the
// main actor at runtime. The compiler can't prove that from the dispatch
// queue alone, so we assert it with `@preconcurrency` (the delegate protocol
// itself is not actor-annotated). Each method then runs in main-actor context.
extension BLEScanner: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Map the CoreBluetooth framework state to the domain enum at this
        // boundary so the published value carries no CoreBluetooth type.
        bluetoothState = BluetoothPowerState(rawState: central.state.rawValue)
        stateResolved = true
        AppLog.record(
            .bluetooth,
            level: bluetoothState.needsUserAction ? .warning : .info,
            code: "bluetooth_state_changed",
            outcome: bluetoothState == .poweredOn ? .success : .observed,
            message: "블루투스 어댑터 상태 변경",
            metadata: [
                "state": bluetoothState.logDescription,
                "scan_requested": String(scanDemand.isRequested)
            ]
        )
        // Only auto-resume if scanning was actually requested. Without this
        // gate a toggled-off AutoLock would silently restart scanning the
        // moment CoreBluetooth reports poweredOn.
        if ScanPolicy.shouldScan(requested: scanDemand.isRequested, poweredOn: central.state == .poweredOn) {
            ensureScanning()
        } else {
            isScanning = false
        }
    }

    public func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        // Ignore late callbacks that arrive after we stopped scanning. Without
        // this, a delayed discovery could re-populate `devices` after
        // stopScanning() cleared it, and with the prune timer off the stale
        // entry would linger until the next scan session.
        guard isScanning else { return }

        let id = peripheral.identifier
        let rssi = RSSI.intValue
        // RSSI of 127 is "unknown" per CoreBluetooth docs
        guard rssi != 127, rssi < 0 else { return }

        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        // Prefer any real name we've ever seen for this peripheral. Android nRF Connect
        // splits the name into the scan response, which arrives in a separate callback.
        // The resolver treats nil/empty/"Unknown" uniformly so a placeholder
        // peripheral.name can't shadow a real advertised name.
        let displayName = DeviceNameResolver.resolve(
            peripheralName: peripheral.name,
            advertisedName: advName,
            existingName: devices[id]?.name
        )

        let smoothed = smoother.update(id: id, rawRssi: rssi)

        devices[id] = DiscoveredDevice(
            id: id,
            name: displayName,
            smoothedRssi: smoothed,
            // Monotonic instant so device age stays correct across wall-clock
            // jumps. Must share the same clock as ProximityController.now.
            lastSeen: MonotonicClock.now()
        )
    }
}
