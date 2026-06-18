import Foundation
import CoreBluetooth
import Combine
import AutoLockCore

@MainActor
public final class BLEScanner: NSObject, ObservableObject, ProximityScanning {
    @Published public private(set) var devices: [UUID: DiscoveredDevice] = [:]
    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    @Published public private(set) var isScanning: Bool = false
    /// True once we've called `centralManagerDidUpdateState` at least once. Until
    /// then `bluetoothState == .unknown` because CoreBluetooth hasn't reported in.
    @Published public private(set) var stateResolved: Bool = false

    private var central: CBCentralManager!
    private var smoother = RssiSmoother()
    private var pruneTimer: Timer?
    /// Whether scanning has been requested (feature on / diagnostic asked).
    /// Recorded even while Bluetooth is off so a later `.poweredOn` callback can
    /// resume — but auto-resume only happens when this is true, so a toggled-off
    /// AutoLock no longer silently restarts scanning. See `ScanPolicy`.
    private var scanRequested = false

    /// Supplies the current user grace period so pruning stays in sync with the
    /// proximity state machine. The pruner MUST evict later than the absence
    /// (instant-lock) point — see `LockTuning.pruneAfterSeconds` — otherwise the
    /// stale/absence lock branches in `ProximityEvaluator` become unreachable.
    /// `ProximityController` wires this to `Settings.gracePeriodSeconds`. When
    /// unset we fall back to the maximum grace so we never prune too soon.
    public var gracePeriodProvider: @MainActor () -> Int = { LockTuning.maxGracePeriodSeconds }

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func startScanning() {
        // Record the request even if Bluetooth isn't ready yet, so the
        // poweredOn callback can resume scanning later.
        scanRequested = true
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
        scanRequested = false
        if central.isScanning { central.stopScan() }
        isScanning = false
        pruneTimer?.invalidate()
        pruneTimer = nil
        // Drop discovered devices and their smoothing state. Pruning is paused
        // while stopped, so without this a long-disabled scanner would keep
        // stale `lastSeen` entries; on re-enable the first evaluate() could see
        // an age past the absence point and lock instantly before any fresh
        // advertisement arrives.
        devices = [:]
        smoother.prune(keeping: [])
    }

    /// Evict devices silent longer than the grace-derived prune threshold,
    /// computed from the live grace period. The smoother is pruned in lockstep
    /// so a rotated/departed device leaves no EWMA state behind.
    func clearStale() {
        let threshold = LockTuning.pruneAfterSeconds(gracePeriodSeconds: gracePeriodProvider())
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
        bluetoothState = central.state
        stateResolved = true
        // Only auto-resume if scanning was actually requested. Without this
        // gate a toggled-off AutoLock would silently restart scanning the
        // moment CoreBluetooth reports poweredOn.
        if ScanPolicy.shouldScan(requested: scanRequested, poweredOn: central.state == .poweredOn) {
            startScanning()
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
