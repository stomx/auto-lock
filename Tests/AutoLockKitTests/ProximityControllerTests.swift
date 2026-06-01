import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

// MARK: - 가짜 의존성

final class FakeScanner: ProximityScanning {
    var devices: [UUID: DiscoveredDevice] = [:]
    var gracePeriodProvider: () -> Int = { 60 }
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startScanning() { startCount += 1 }
    func stopScanning() { stopCount += 1 }
}

final class SpyScreenLocker: ScreenLocking {
    var lockedState = false
    private(set) var lockCount = 0

    func lock() -> Bool {
        lockCount += 1
        lockedState = true
        return true
    }
    func isScreenLocked() -> Bool { lockedState }
}

@MainActor
final class SpyOverlay: OverlayPresenting {
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var lastDeadline: Date? = nil

    func show(until deadline: Date) {
        showCount += 1
        lastDeadline = deadline
    }
    func hide() { hideCount += 1 }
}

final class SpyWaker: DisplayWaking {
    private(set) var wakeCount = 0
    func wake() -> Bool { wakeCount += 1; return true }
}

final class SpyUnlocker: UnlockTriggering {
    private(set) var attemptCount = 0
    var result: UnlockOutcome = .dispatched
    func attempt() -> UnlockOutcome { attemptCount += 1; return result }
}

// MARK: - 테스트

@MainActor
@Suite struct ProximityControllerTests {

    private let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
    private let deviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// 격리된 UserDefaults suite로 Settings를 만든다.
    private func makeSettings() -> Settings {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return Settings(defaults: defaults)
    }

    /// 모든 가짜를 묶어서 컨트롤러를 조립한다. now는 고정 시각으로 주입.
    private func makeController(
        settings: Settings,
        scanner: FakeScanner = FakeScanner(),
        locker: SpyScreenLocker = SpyScreenLocker(),
        overlay: SpyOverlay? = nil,
        waker: SpyWaker = SpyWaker(),
        unlocker: SpyUnlocker = SpyUnlocker()
    ) -> ProximityController {
        let overlay = overlay ?? SpyOverlay()
        let c = ProximityController(
            scanner: scanner,
            settings: settings,
            screenLocker: locker,
            overlay: overlay,
            waker: waker,
            unlocker: unlocker
        )
        c.now = { [now] in now }
        return c
    }

    private func discovered(rssi: Double, ageSeconds: TimeInterval) -> DiscoveredDevice {
        DiscoveredDevice(id: deviceID, name: "watch", smoothedRssi: rssi, lastSeen: now.addingTimeInterval(-ageSeconds))
    }

    // 1. enabled=false → evaluate 시 overlay.hide + idle
    @Test func disabledHidesOverlayAndIdles() {
        let settings = makeSettings()
        settings.enabled = false
        let overlay = SpyOverlay()
        let c = makeController(settings: settings, overlay: overlay)

        c.evaluate()

        #expect(c.state == .unknown)
        #expect(c.status == .idle)
        #expect(overlay.hideCount >= 1)
    }

    // 2. enabled=true, trackedDevices 비어있음 → awaitingDevice
    @Test func enabledNoDevicesAwaits() {
        let settings = makeSettings()
        settings.enabled = true
        let c = makeController(settings: settings)

        c.evaluate()

        #expect(c.state == .unknown)
        #expect(c.status == .awaitingDevice)
    }

    // 3. best 기기 강신호+최근 → near, lock 미호출
    @Test func nearDoesNotLock() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70   // threshold -70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()

        #expect(c.state == .near)
        #expect(locker.lockCount == 0)
    }

    // 4. age > absence point → 즉시 lock
    @Test func staleAgeLocks() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.gracePeriodSeconds = 15      // absence point = 30
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 31)]
        let locker = SpyScreenLocker()
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()

        #expect(c.state == .away)
        #expect(locker.lockCount == 1)
    }

    // 5. RSSI 급락(definitiveAway 이하) → lock
    @Test func crashedRssiLocks() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70      // threshold -70, definitiveAway -80
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -95, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()

        #expect(locker.lockCount == 1)
    }

    // 6. grace 윈도우 final stretch → overlay.show(deadline)
    @Test func overlayWindowShows() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70      // threshold -70
        settings.gracePeriodSeconds = 15
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        // 약신호(-75)로 away 카운트다운 진입. 첫 evaluate에서 awaySince=now가 잡힌다.
        // remaining = 15 → hideOverlay. overlay 표시를 보려면 awaySince가 과거여야 하므로
        // 두 번 평가하되 두 번째 now를 앞당기는 대신, 신호 약함을 유지하고 now를 deadline 근처로.
        scanner.devices = [deviceID: discovered(rssi: -75, ageSeconds: 1)]
        let overlay = SpyOverlay()
        let c = makeController(settings: settings, scanner: scanner, overlay: overlay)

        // 첫 평가: awaySince = now 설정 (remaining 15 → hideOverlay)
        c.evaluate()
        // now를 12초 앞으로 옮겨 remaining=3 (≤5) → showOverlay
        c.now = { [now] in now.addingTimeInterval(12) }
        // lastSeen도 동일하게 최신화해 stale 분기로 빠지지 않게 한다(age는 13s < grace15).
        scanner.devices = [deviceID: DiscoveredDevice(id: deviceID, name: "watch", smoothedRssi: -75, lastSeen: now.addingTimeInterval(11))]
        c.evaluate()

        #expect(overlay.showCount >= 1)
        #expect(overlay.lastDeadline != nil)
    }

    // 7a. 화면 잠김+강신호+autoUnlock off → waker.wake
    @Test func wakesDisplayWhenLocked() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70      // threshold -70, wake 경계 -50
        settings.wakeOnProximity = true
        settings.autoUnlock = false
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -40, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        locker.lockedState = true
        let waker = SpyWaker()
        let unlocker = SpyUnlocker()
        let c = makeController(settings: settings, scanner: scanner, locker: locker, waker: waker, unlocker: unlocker)

        c.evaluate()

        #expect(c.state == .near)
        #expect(waker.wakeCount == 1)
        #expect(unlocker.attemptCount == 0)
    }

    // 7b. 화면 잠김+강신호+autoUnlock on → unlocker.attempt
    @Test func attemptsUnlockWhenLocked() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.wakeOnProximity = true
        settings.autoUnlock = true
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -40, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        locker.lockedState = true
        let waker = SpyWaker()
        let unlocker = SpyUnlocker()
        let c = makeController(settings: settings, scanner: scanner, locker: locker, waker: waker, unlocker: unlocker)

        c.evaluate()

        #expect(unlocker.attemptCount == 1)
        #expect(waker.wakeCount == 0)
    }

    // 8. settings.enabled 토글 → scanner.start/stopScanning ($enabled sink)
    @Test func enabledTogglesScanner() {
        let settings = makeSettings()
        settings.enabled = false
        let scanner = FakeScanner()
        let c = makeController(settings: settings, scanner: scanner)
        _ = c   // 구독 유지

        // init 시점에 enabled=false를 1회 받아 stopScanning 호출됨.
        let baselineStop = scanner.stopCount

        settings.enabled = true
        #expect(scanner.startCount == 1)

        settings.enabled = false
        #expect(scanner.stopCount == baselineStop + 1)
    }
}
