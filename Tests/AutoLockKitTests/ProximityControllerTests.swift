import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

// MARK: - 가짜 의존성

@MainActor
final class FakeScanner: ProximityScanning {
    var devices: [UUID: DiscoveredDevice] = [:]
    var gracePeriodProvider: @MainActor () -> Int = { 60 }
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startScanning() { startCount += 1 }
    func stopScanning() { stopCount += 1 }
}

final class SpyScreenLocker: ScreenLocking {
    var lockedState = false
    /// When false, lock() reports failure and does NOT flip lockedState —
    /// simulating the private lock symbol being unavailable.
    var lockSucceeds = true
    private(set) var lockCount = 0

    func lock() -> Bool {
        lockCount += 1
        if lockSucceeds { lockedState = true }
        return lockSucceeds
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
        scanner: FakeScanner? = nil,
        locker: SpyScreenLocker = SpyScreenLocker(),
        overlay: SpyOverlay? = nil,
        waker: SpyWaker = SpyWaker(),
        unlocker: SpyUnlocker = SpyUnlocker()
    ) -> ProximityController {
        // FakeScanner/SpyOverlay are @MainActor (ProximityScanning is now
        // MainActor-isolated), so they can't be evaluated as default arguments
        // in a nonisolated context — construct them here inside the suite.
        let scanner = scanner ?? FakeScanner()
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
    //    grace 고정 15초 → absence point = 15*2 = 30초. age 31 > 30.
    @Test func staleAgeLocks() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
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
    //    grace 고정 15초, 오버레이 윈도우 마지막 5초.
    @Test func overlayWindowShows() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70      // threshold -70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        // 약신호(-75)로 away 카운트다운 진입. 첫 evaluate에서 awaySince=now가 잡힌다.
        // remaining = 15 → hideOverlay. overlay 표시를 보려면 awaySince가 과거여야 하므로
        // now를 11초 앞으로 옮겨 remaining=4 (≤5)로 만든다.
        scanner.devices = [deviceID: discovered(rssi: -75, ageSeconds: 1)]
        let overlay = SpyOverlay()
        let c = makeController(settings: settings, scanner: scanner, overlay: overlay)

        // 첫 평가: awaySince = now 설정 (remaining 15 → hideOverlay)
        c.evaluate()
        // now를 11초 앞으로 옮겨 remaining=4 (≤5) → showOverlay
        c.now = { [now] in now.addingTimeInterval(11) }
        // lastSeen도 최신화해 stale 분기로 빠지지 않게 한다(age는 1s < grace15).
        scanner.devices = [deviceID: DiscoveredDevice(id: deviceID, name: "watch", smoothedRssi: -75, lastSeen: now.addingTimeInterval(10))]
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

    // 7c. 화면 잠김+강신호+autoUnlock on이지만 attempt 실패(.noPassword)
    //     → fallback으로 화면을 깨운다(회귀 방지: 검은 화면 방치 금지).
    @Test func unlockFailureFallsBackToWake() {
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
        unlocker.result = .noPassword
        let c = makeController(settings: settings, scanner: scanner, locker: locker, waker: waker, unlocker: unlocker)

        c.evaluate()

        #expect(unlocker.attemptCount == 1)
        #expect(waker.wakeCount == 1)   // 실패 → fallback wake
    }

    // 7d. attempt 성공(.dispatched) → fallback wake 없음.
    @Test func unlockDispatchedSkipsFallbackWake() {
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
        unlocker.result = .dispatched
        let c = makeController(settings: settings, scanner: scanner, locker: locker, waker: waker, unlocker: unlocker)

        c.evaluate()

        #expect(unlocker.attemptCount == 1)
        #expect(waker.wakeCount == 0)   // 성공 → fallback 불필요
    }

    // 10a. 토글을 끄면 직전 RSSI(bestSeen)가 UI에 남지 않도록 nil로 정리된다.
    @Test func disablingClearsBestSeen() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 1)]
        let c = makeController(settings: settings, scanner: scanner)

        c.evaluate()
        #expect(c.bestSeen != nil)   // near 상태로 채워짐

        settings.enabled = false
        c.evaluate()
        #expect(c.bestSeen == nil)   // 비활성화 시 정리
    }

    // 10b. 등록 디바이스를 모두 제거하면 bestSeen이 정리된다.
    @Test func removingDevicesClearsBestSeen() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 1)]
        let c = makeController(settings: settings, scanner: scanner)

        c.evaluate()
        #expect(c.bestSeen != nil)

        settings.removeDevice(id: deviceID)
        c.evaluate()
        #expect(c.bestSeen == nil)
    }

    // 10c. 토글 OFF 즉시(다음 evaluate 전) bestSeen/state/status가 정리된다.
    //      ($enabled sink가 stopScanning만 하고 UI 상태를 안 지우면 1초간 stale RSSI 노출)
    @Test func disablingImmediatelyClearsUIState() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 1)]
        let overlay = SpyOverlay()
        let c = makeController(settings: settings, scanner: scanner, overlay: overlay)

        c.evaluate()
        #expect(c.bestSeen != nil)
        #expect(c.state == .near)

        // 토글만 끄고 evaluate는 호출하지 않는다 — sink가 즉시 정리해야 한다.
        settings.enabled = false

        #expect(c.bestSeen == nil)
        #expect(c.state == .unknown)
        #expect(c.status == .idle)
    }

    // 9a. lock() 실패 → status는 .lockFailed (성공 잠금으로 위장 금지).
    @Test func lockFailureReportsLockFailed() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))   // grace 고정 10 → absence 20
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 31)]
        let locker = SpyScreenLocker()
        locker.lockSucceeds = false
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()

        #expect(locker.lockCount == 1)
        if case .lockFailed = c.status {} else {
            Issue.record("expected .lockFailed, got \(c.status)")
        }
    }

    // 9b. lock() 계속 실패 → 다음 tick에서도 재시도(백오프 없음).
    @Test func lockFailureRetriesNextTick() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))   // grace 고정 10 → absence 20
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 31)]
        let locker = SpyScreenLocker()
        locker.lockSucceeds = false
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()
        c.evaluate()

        #expect(locker.lockCount == 2)   // 매 tick 재시도
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
