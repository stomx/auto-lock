import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

// MARK: - 가짜 의존성

@MainActor
final class FakeScanner: ProximityScanning {
    var devices: [UUID: DiscoveredDevice] = [:]
    var gracePeriodProvider: @MainActor () -> Int = { 60 }
    var countdownPeriodProvider: @MainActor () -> Int = { 30 }
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startScanning() { startCount += 1 }
    func stopScanning() { stopCount += 1 }
}

final class SpyScreenLocker: ScreenLocking {
    var lockedState = false
    var reportedState: ScreenLockState?
    /// When false, lock() reports failure and does NOT flip lockedState —
    /// simulating the private lock symbol being unavailable.
    var lockSucceeds = true
    var changesStateOnLock = true
    private(set) var lockCount = 0

    func lock() -> Bool {
        lockCount += 1
        if lockSucceeds && changesStateOnLock { lockedState = true }
        return lockSucceeds
    }
    func isScreenLocked() -> Bool { lockedState }
    func screenLockState() -> ScreenLockState {
        reportedState ?? (lockedState ? .locked : .unlocked)
    }
}

final class DefaultStateScreenLocker: ScreenLocking {
    var lockedState = false
    func lock() -> Bool { true }
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
    var succeeds = true
    func wake() -> Bool { wakeCount += 1; return succeeds }
}

final class SpyUnlocker: UnlockTriggering {
    private(set) var attemptCount = 0
    var result: UnlockOutcome = .dispatched
    var onAttempt: (() -> Void)?
    func attempt() -> UnlockOutcome {
        attemptCount += 1
        onAttempt?()
        return result
    }
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

    @Test func defaultScreenStateAdapterMapsBooleanProbe() {
        let locker = DefaultStateScreenLocker()
        #expect(locker.screenLockState() == .unlocked)
        locker.lockedState = true
        #expect(locker.screenLockState() == .locked)
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

    // 4. 기본 무신호 10초 + 카운트다운 5초가 끝난 age 15 → lock.
    @Test func staleAgeLocks() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 15)]
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

    // 6. 약신호는 설정된 카운트다운 전체를 즉시 표시한다.
    @Test func weakSignalShowsConfiguredCountdown() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70      // threshold -70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -75, ageSeconds: 1)]
        let overlay = SpyOverlay()
        let c = makeController(settings: settings, scanner: scanner, overlay: overlay)

        c.evaluate()

        #expect(overlay.showCount >= 1)
        #expect(overlay.lastDeadline == now.addingTimeInterval(5))
    }

    // 7a. 화면 잠김+강신호+autoUnlock off → waker.wake
    @Test func wakesDisplayWhenLocked() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70      // threshold -70, wake 경계 -60
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
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 15)]
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
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 15)]
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
        #expect(scanner.gracePeriodProvider() == 10)
        #expect(scanner.countdownPeriodProvider() == 5)

        // init 시점에 enabled=false를 1회 받아 stopScanning 호출됨.
        let baselineStop = scanner.stopCount

        settings.enabled = true
        #expect(scanner.startCount == 1)

        settings.enabled = false
        #expect(scanner.stopCount == baselineStop + 1)
    }

    @Test func menuBarIconRepresentsEveryControllerState() {
        let settings = makeSettings()
        let scanner = FakeScanner()
        let c = makeController(settings: settings, scanner: scanner)
        #expect(c.menuBarIcon == "lock.open.fill")       // disabled

        settings.enabled = true
        c.evaluate()
        #expect(c.menuBarIcon == "lock.slash")           // unknown

        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        scanner.devices = [deviceID: discovered(rssi: -50, ageSeconds: 1)]
        c.evaluate()
        #expect(c.menuBarIcon == "lock.open.fill")       // near

        scanner.devices = [deviceID: discovered(rssi: -75, ageSeconds: 1)]
        c.evaluate()
        #expect(c.menuBarIcon == "lock.rotation")        // borderline

        scanner.devices = [deviceID: discovered(rssi: -95, ageSeconds: 1)]
        c.evaluate()
        #expect(c.menuBarIcon == "lock.fill")            // away
    }

    @Test func evaluationTimerActuallyEvaluates() async throws {
        let settings = makeSettings()
        settings.enabled = true
        let c = makeController(settings: settings)
        #expect(c.status == .watching)
        try await Task.sleep(for: .seconds(1.1))
        #expect(c.status == .awaitingDevice)
    }

    @Test func observesScreenStateEvenWhenMonitoringIsDisabled() {
        let settings = makeSettings()
        settings.enabled = false
        let locker = SpyScreenLocker()
        let c = makeController(settings: settings, locker: locker)

        c.evaluate()
        #expect(c.screenLockState == .unlocked)

        locker.lockedState = true
        c.evaluate()
        #expect(c.screenLockState == .locked)

        locker.reportedState = .unknown
        c.evaluate()
        #expect(c.screenLockState == .unknown)
        #expect(c.recentEvents.contains {
            $0.code == "screen_state_changed" && $0.level == .warning
        })
    }

    @Test func manualLockConfirmsAndSkipsWhenAlreadyLocked() {
        let settings = makeSettings()
        let locker = SpyScreenLocker()
        let c = makeController(settings: settings, locker: locker)

        c.lockNow()
        #expect(locker.lockCount == 1)
        #expect(c.screenLockState == .locked)
        if case .locked(reason: .userRequested) = c.status {} else {
            Issue.record("expected confirmed manual lock, got \(c.status)")
        }

        c.lockNow()
        #expect(locker.lockCount == 1)
    }

    @Test func acceptedLockWaitsForScreenConfirmationWithoutDuplicateRequest() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -95, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        locker.changesStateOnLock = false
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()
        if case .lockRequested = c.status {} else {
            Issue.record("expected pending lock, got \(c.status)")
        }
        c.lockNow()
        #expect(locker.lockCount == 1)
        c.now = { [now] in now.addingTimeInterval(1) }
        c.evaluate()
        #expect(locker.lockCount == 1)

        locker.lockedState = true
        c.now = { [now] in now.addingTimeInterval(2) }
        c.evaluate()
        #expect(c.screenLockState == .locked)
        if case .locked = c.status {} else {
            Issue.record("expected confirmed lock, got \(c.status)")
        }
    }

    @Test func acceptedButUnconfirmedLockTimesOutAsFailure() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -95, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        locker.changesStateOnLock = false
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()
        c.now = { [now] in now.addingTimeInterval(6) }
        c.evaluate()

        if case .lockFailed = c.status {} else {
            Issue.record("expected confirmation timeout failure, got \(c.status)")
        }
        #expect(locker.lockCount == 1)
        #expect(c.recentEvents.contains { $0.code == "screen_lock_confirmation_timeout" })
    }

    @Test func dispatchedUnlockIsConfirmedByObservedScreenOpening() {
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
        let unlocker = SpyUnlocker()
        unlocker.result = .dispatched
        let c = makeController(settings: settings, scanner: scanner, locker: locker, unlocker: unlocker)

        c.evaluate()
        locker.lockedState = false
        c.now = { [now] in now.addingTimeInterval(1) }
        c.evaluate()

        #expect(c.screenLockState == .unlocked)
        #expect(c.recentEvents.contains { $0.code == "screen_unlock_confirmed" })
    }

    @Test func dispatchedUnlockTimeoutRecordsFailure() {
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
        let unlocker = SpyUnlocker()
        unlocker.result = .dispatched
        let c = makeController(settings: settings, scanner: scanner, locker: locker, unlocker: unlocker)

        c.evaluate()
        c.now = { [now] in now.addingTimeInterval(6) }
        c.evaluate()

        #expect(c.recentEvents.contains { $0.code == "screen_unlock_confirmation_timeout" })
    }

    @Test func immediatelyUnlockedOutcomeIsVerified() {
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
        let unlocker = SpyUnlocker()
        unlocker.result = .unlocked
        unlocker.onAttempt = { locker.lockedState = false }
        let c = makeController(settings: settings, scanner: scanner, locker: locker, unlocker: unlocker)

        c.evaluate()

        #expect(c.screenLockState == .unlocked)
        #expect(c.recentEvents.contains { $0.code == "screen_unlock_confirmed" })
    }

    @Test func wakeFailuresAndUnlockPreflightReasonsAreSurfaced() {
        for outcome in [UnlockOutcome.noAccessibility, .eventSourceUnavailable] {
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
            let unlocker = SpyUnlocker()
            unlocker.result = outcome
            let waker = SpyWaker()
            waker.succeeds = false
            let c = makeController(
                settings: settings,
                scanner: scanner,
                locker: locker,
                waker: waker,
                unlocker: unlocker
            )

            c.evaluate()
            #expect(c.recentEvents.contains {
                $0.code == "fallback_display_wake" && $0.outcome == .failure
            })
        }

        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.wakeOnProximity = true
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -40, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        locker.lockedState = true
        let waker = SpyWaker()
        waker.succeeds = false
        let c = makeController(settings: settings, scanner: scanner, locker: locker, waker: waker)
        c.evaluate()
        #expect(c.recentEvents.contains {
            $0.code == "display_wake_requested" && $0.outcome == .failure
        })
    }

    @Test func countdownExpiryLogsNonInstantLockDecision() {
        let settings = makeSettings()
        settings.enabled = true
        settings.thresholdMagnitude = 70
        settings.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        let scanner = FakeScanner()
        scanner.devices = [deviceID: discovered(rssi: -75, ageSeconds: 1)]
        let locker = SpyScreenLocker()
        let c = makeController(settings: settings, scanner: scanner, locker: locker)

        c.evaluate()
        c.now = { [now] in now.addingTimeInterval(5) }
        scanner.devices = [
            deviceID: DiscoveredDevice(
                id: deviceID,
                name: "watch",
                smoothedRssi: -75,
                lastSeen: now.addingTimeInterval(4)
            )
        ]
        c.evaluate()

        #expect(locker.lockCount == 1)
        #expect(c.recentEvents.contains {
            $0.code == "proximity_state_changed" && $0.message.contains("잠금 유예가 끝나")
        })
    }
}
