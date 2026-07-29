import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

// MARK: - 가상 디바이스 타임라인 리플레이
//
// 기존 ProximityControllerTests는 "한 틱"만 평가해 상태 전이의 정적 단면을
// 검증한다. 이 Suite는 그것이 못 잡는 부분 — 시간이 흐르며 awaySince가
// 누적되고, BLE 프루너가 디바이스를 지우는 시점과 잠금 시점이 경합하는
// **닫힌 루프** — 을 실제 `ProximityController`에 가짜 스캐너를 물려 1Hz로
// 흘려보내 실측한다.
//
// Spy/Fake 정의(FakeScanner, SpyScreenLocker, SpyOverlay, SpyWaker,
// SpyUnlocker)는 같은 테스트 타깃의 ProximityControllerTests.swift에 이미
// 있으므로 여기서 재정의하지 않고 그대로 재사용한다.

@MainActor
@Suite struct ProximityTimelineTests {

    /// 기준 시각. 모든 틱은 t0 + N초로 표현한다.
    private let t0 = Date(timeIntervalSinceReferenceDate: 3_000_000)
    private let deviceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private let defaultGrace = LockSettingBounds.defaultGracePeriodSeconds
    private let defaultCountdown = LockSettingBounds.defaultCountdownSeconds

    /// 격리된 UserDefaults suite로 Settings를 만든다.
    private func makeSettings(magnitude: Int, grace: Int, countdown: Int) -> Settings {
        let suite = "timeline-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let s = Settings(defaults: defaults)
        s.enabled = true
        s.thresholdMagnitude = magnitude     // threshold = -magnitude
        s.gracePeriodSeconds = grace
        s.countdownSeconds = countdown
        // wake/unlock 경로가 near 상태에서 끼어들지 않도록 비활성화 — 이 Suite는
        // 잠금 루프만 본다. (화면은 항상 unlocked로 두므로 lock()은 1회만 먹힌다.)
        s.wakeOnProximity = false
        s.autoUnlock = false
        s.addDevice(TrackedDevice(id: deviceID, name: "watch"))
        return s
    }

    /// 한 틱의 관측 스냅샷.
    private struct Frame {
        let tick: Int
        let state: ProximityState
        let status: ControllerStatus
        let lockCount: Int
        let showCount: Int
        /// 이 틱의 evaluate() 시점에 스캐너 맵에 디바이스가 존재했는가.
        let devicePresent: Bool
    }

    /// 시나리오 함수: tick → (rssi, lastSeenTick)? 를 반환.
    /// nil이면 "이번 틱 광고 없음" — lastSeen이 직전 값에 동결된다.
    private typealias Scenario = (Int) -> (rssi: Double, lastSeenTick: Int)?

    /// 타임라인을 0..=lastTick 까지 1Hz로 리플레이하고 매 틱 Frame을 기록한다.
    ///
    /// 매 틱:
    ///  1. c.now 를 t0 + tick초 로 전진
    ///  2. 시나리오로 광고 상태 결정 (nil이면 lastSeen 동결)
    ///  3. 실제 프루너 모사: age > pruneAfter(grace) 이면 맵에서 제거
    ///     (BLEScanner.clearStale 규칙), 아니면 갱신
    ///  4. evaluate()
    ///  5. 관측치 기록
    private func replay(
        magnitude: Int,
        grace: Int? = nil,
        countdown: Int? = nil,
        through lastTick: Int,
        locker: SpyScreenLocker = SpyScreenLocker(),
        overlay: SpyOverlay? = nil,
        scenario: Scenario
    ) -> [Frame] {
        let overlay = overlay ?? SpyOverlay()
        let grace = grace ?? defaultGrace
        let countdown = countdown ?? defaultCountdown
        let settings = makeSettings(magnitude: magnitude, grace: grace, countdown: countdown)
        let scanner = FakeScanner()
        let c = ProximityController(
            scanner: scanner,
            settings: settings,
            screenLocker: locker,
            overlay: overlay,
            waker: SpyWaker(),
            unlocker: SpyUnlocker()
        )

        let pruneAfter = LockTuning.pruneAfterSeconds(
            gracePeriodSeconds: grace,
            countdownSeconds: countdown
        )

        // 시나리오가 광고를 멈춰도 직전 lastSeen/rssi를 이어가야 하므로 누적 보관.
        var frozenLastSeenTick: Int? = nil
        var frozenRssi: Double = 0

        var frames: [Frame] = []
        for tick in 0...lastTick {
            let nowDate = t0.addingTimeInterval(TimeInterval(tick))
            c.now = { nowDate }

            if let sample = scenario(tick) {
                frozenLastSeenTick = sample.lastSeenTick
                frozenRssi = sample.rssi
            }

            // 프루너 모사 + 맵 갱신.
            if let ls = frozenLastSeenTick {
                let age = TimeInterval(tick - ls)
                if age <= pruneAfter {
                    scanner.devices[deviceID] = DiscoveredDevice(
                        id: deviceID,
                        name: "watch",
                        smoothedRssi: frozenRssi,
                        lastSeen: t0.addingTimeInterval(TimeInterval(ls))
                    )
                } else {
                    scanner.devices[deviceID] = nil
                }
            }

            c.evaluate()

            frames.append(Frame(
                tick: tick,
                state: c.state,
                status: c.status,
                lockCount: locker.lockCount,
                showCount: overlay.showCount,
                devicePresent: scanner.devices[deviceID] != nil
            ))
        }
        return frames
    }

    /// status가 카운트다운 계열인지. countdown은 연관값을 가지므로 패턴매칭.
    private func isCountdown(_ s: ControllerStatus) -> Bool {
        if case .countdown = s { return true }
        return false
    }

    // MARK: - 1. 광고 중단 → 카운트다운 → 잠금 (닫힌 루프 핵심)
    //
    // 기본 grace=10, countdown=5, threshold -70. tick0~5 강신호 광고 →
    // near. tick6부터 광고 중단(lastSeen=5 동결). age=10인 tick15부터
    // 카운트다운, age=15인 tick20에서 잠금이 발화한다.
    //
    // 핵심 불변식: 잠금이 발화한 틱(t=20, age=15)에서 age(15) ≤ prune(17)이라
    // 디바이스가 아직 맵에 살아있다 — 프루너가 잠금보다 늦게 evict한다.
    @Test func awayByStaleThenLocks() {
        let frames = replay(magnitude: 70, through: 24) { tick in
            tick <= 5 ? (rssi: -50, lastSeenTick: tick) : nil
        }

        // 초반엔 near.
        #expect(frames[0].state == .near)
        #expect(frames[5].state == .near)
        #expect(frames.prefix(20).allSatisfy { $0.lockCount == 0 })

        // lastSeen=5 → tick15(age10)부터 5초 카운트다운.
        #expect(isCountdown(frames[15].status))
        #expect(frames[15].state == .borderline)

        // 결국 잠금이 발화한다.
        let lockTick = frames.first { $0.lockCount == 1 }?.tick
        #expect(lockTick != nil)
        #expect(frames.last!.lockCount == 1)   // 단 한 번만 (화면 잠긴 뒤 재발화 없음)

        // 결정적 불변식: 잠금 발화 시점에 디바이스가 맵에 존재했다.
        let lockFrame = frames.first { $0.lockCount == 1 }!
        #expect(lockFrame.devicePresent == true)
        #expect(lockFrame.state == .away)

        #expect(lockFrame.tick == 20)
    }

    // MARK: - 2. 이탈 중 복귀 → 잠금 안 됨
    //
    // 기본 10+5초. tick0~5 near, tick6~18 광고 중단, tick19부터 강신호
    // 광고 재개 → 카운트다운 종료 직전 near 회복, 잠금 0.
    @Test func returnsToNearBeforeLock() {
        let frames = replay(magnitude: 70, through: 25) { tick in
            if tick <= 5 { return (rssi: -50, lastSeenTick: tick) }
            if tick <= 18 { return nil }            // 광고 중단
            return (rssi: -50, lastSeenTick: tick)  // 복귀
        }

        // 이탈 중 카운트다운에 실제로 진입했다.
        #expect(frames.contains { isCountdown($0.status) })

        // 복귀 후 near 회복.
        #expect(frames[19].state == .near)
        #expect(frames.last!.state == .near)

        // 전체 시퀀스에서 단 한 번도 잠기지 않는다.
        #expect(frames.allSatisfy { $0.lockCount == 0 })
    }

    // MARK: - 3. 신호 약화형 → 급락 즉시잠금
    //
    // threshold -70(defAway -80). 디바이스는 계속 광고(lastSeen 매
    // 틱 갱신)하지만 rssi가 -50에서 매 틱 -3씩 약해진다.
    // near(-50~-68) → 약신호 카운트다운(-71~-77) → -80 도달 시 즉시잠금(crashed).
    // lastSeen이 항상 fresh라 무신호 설정과 무관하게 잠긴다(t10, rssi -80).
    @Test func weakeningSignalCrashesToLock() {
        let frames = replay(magnitude: 70, through: 15) { tick in
            (rssi: -50 - 3 * Double(tick), lastSeenTick: tick)
        }

        // 강신호 구간은 near.
        #expect(frames[0].state == .near)
        #expect(frames[6].state == .near)   // rssi -68, 아직 threshold -70 위

        // threshold와 defAway 사이(-71 ~ -77) 약신호 카운트다운.
        #expect(isCountdown(frames[7].status))   // rssi -71
        #expect(frames[7].state == .borderline)

        // -80 도달 시 즉시잠금.
        let lockFrame = frames.first { $0.lockCount == 1 }!
        #expect(lockFrame.tick == 10)            // rssi -80
        #expect(lockFrame.state == .away)
        // 신호 약화형은 광고가 계속되므로 잠금 시점에도 디바이스가 항상 존재.
        #expect(lockFrame.devicePresent == true)

        #expect(frames.last!.lockCount == 1)
    }

    // MARK: - 4. 카운트다운 오버레이 표시 타이밍
    //
    // 시나리오1과 동일 입력. 10초 무신호 허용 동안은 숨기고, 설정된 5초
    // 카운트다운 전체(t15~t19)를 표시한다.
    @Test func staleCountdownShowsOverlayForConfiguredDuration() {
        let overlay = SpyOverlay()
        let frames = replay(magnitude: 70, through: 20, overlay: overlay) { tick in
            tick <= 5 ? (rssi: -50, lastSeenTick: tick) : nil
        }

        #expect(frames.first { $0.showCount > 0 }!.tick == 15)
        #expect(frames.prefix(15).allSatisfy { $0.showCount == 0 })

        #expect(overlay.showCount >= 1)
        #expect(overlay.lastDeadline != nil)

        let expectedDeadline = t0.addingTimeInterval(20)
        #expect(abs(overlay.lastDeadline!.timeIntervalSince(expectedDeadline)) < 0.001)
    }

    @Test func customTimingControlsEndToEndLockDeadline() {
        // lastSeen=t2, grace=20, countdown=3 → t22부터 표시, t25 잠금.
        let frames = replay(
            magnitude: 70,
            grace: 20,
            countdown: 3,
            through: 27
        ) { tick in
            tick <= 2 ? (rssi: -50, lastSeenTick: tick) : nil
        }

        #expect(isCountdown(frames[22].status))
        #expect(frames.first { $0.lockCount == 1 }?.tick == 25)
    }
}
