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

    /// grace는 더 이상 사용자 조정 항목이 아니라 15초 고정. 타임라인 테스트도
    /// 이 고정값으로 동작/검증한다.
    private let grace = LockTuning.fixedGracePeriodSeconds

    /// 격리된 UserDefaults suite로 Settings를 만든다.
    private func makeSettings(magnitude: Int) -> Settings {
        let suite = "timeline-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let s = Settings(defaults: defaults)
        s.enabled = true
        s.thresholdMagnitude = magnitude     // threshold = -magnitude
        // grace는 Settings.gracePeriodSeconds가 항상 15초 고정으로 반환.
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
        through lastTick: Int,
        locker: SpyScreenLocker = SpyScreenLocker(),
        overlay: SpyOverlay? = nil,
        scenario: Scenario
    ) -> [Frame] {
        let overlay = overlay ?? SpyOverlay()
        let settings = makeSettings(magnitude: magnitude)
        let scanner = FakeScanner()
        let c = ProximityController(
            scanner: scanner,
            settings: settings,
            screenLocker: locker,
            overlay: overlay,
            waker: SpyWaker(),
            unlocker: SpyUnlocker()
        )

        let pruneAfter = LockTuning.pruneAfterSeconds(gracePeriodSeconds: grace)

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
    // grace=15, threshold -70. tick0~5 강신호 광고 → near. tick6부터 광고
    // 중단(lastSeen=5 동결). age가 grace(15)를 넘는 tick21부터 카운트다운,
    // age가 absence(30)를 넘는 tick36에서 즉시잠금이 발화한다.
    //
    // 핵심 불변식: 잠금이 발화한 틱(t=36, age=31)에서 age(31) ≤ prune(32)이라
    // 디바이스가 아직 맵에 살아있다 — 프루너가 잠금보다 늦게 evict한다.
    @Test func awayByStaleThenLocks() {
        // grace=15 → absence=30, prune=32. lastSeen=5.
        let frames = replay(magnitude: 70, through: 40) { tick in
            tick <= 5 ? (rssi: -50, lastSeenTick: tick) : nil
        }

        // 초반엔 near.
        #expect(frames[0].state == .near)
        #expect(frames[5].state == .near)
        #expect(frames.prefix(21).allSatisfy { $0.lockCount == 0 })

        // age > grace(15) 진입 구간(lastSeen=5 → tick21에서 age16)부터 카운트다운.
        #expect(isCountdown(frames[21].status))
        #expect(frames[21].state == .borderline)

        // 결국 잠금이 발화한다.
        let lockTick = frames.first { $0.lockCount == 1 }?.tick
        #expect(lockTick != nil)
        #expect(frames.last!.lockCount == 1)   // 단 한 번만 (화면 잠긴 뒤 재발화 없음)

        // 결정적 불변식: 잠금 발화 시점에 디바이스가 맵에 존재했다.
        let lockFrame = frames.first { $0.lockCount == 1 }!
        #expect(lockFrame.devicePresent == true)
        #expect(lockFrame.state == .away)

        // 실측 경계: age>absence(30) 첫 틱 = t36(age31). prune(32)은 t38부터라 아직 존재.
        #expect(lockFrame.tick == 36)
    }

    // MARK: - 2. 이탈 중 복귀 → 잠금 안 됨
    //
    // grace=15. tick0~5 near. tick6~23 광고 중단(카운트다운 진입까지 감).
    // tick24부터 강신호 광고 재개 → awaySince 리셋 → near 회복, 잠금 0.
    // (lastSeen=5, age>absence(30)은 t36부터라 복귀 t24가 더 빠르다 → 잠금 0 유지.)
    @Test func returnsToNearBeforeLock() {
        let frames = replay(magnitude: 70, through: 30) { tick in
            if tick <= 5 { return (rssi: -50, lastSeenTick: tick) }
            if tick <= 23 { return nil }            // 광고 중단
            return (rssi: -50, lastSeenTick: tick)  // 복귀
        }

        // 이탈 중 카운트다운에 실제로 진입했다.
        #expect(frames.contains { isCountdown($0.status) })

        // 복귀 후 near 회복.
        #expect(frames[24].state == .near)
        #expect(frames.last!.state == .near)

        // 전체 시퀀스에서 단 한 번도 잠기지 않는다.
        #expect(frames.allSatisfy { $0.lockCount == 0 })
    }

    // MARK: - 3. 신호 약화형 → 급락 즉시잠금
    //
    // grace=15, threshold -70(defAway -80). 디바이스는 계속 광고(lastSeen 매
    // 틱 갱신)하지만 rssi가 -50에서 매 틱 -3씩 약해진다.
    // near(-50~-68) → 약신호 카운트다운(-71~-77) → -80 도달 시 즉시잠금(crashed).
    // lastSeen이 항상 fresh라 grace와 무관하게 rssi 분기로 잠긴다(t10, rssi -80).
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
    // 시나리오1과 동일 입력이되 overlay.show 타이밍에 집중. 카운트다운 deadline
    // 5초 이내(overlayWindowSeconds) 구간에서만 show가 불리고 그 전에는 hide.
    // grace=15: awaySince=t21 → deadline=t36. remaining<=5 인 t31~t35에서 show.
    @Test func staleCountdownShowsOverlayInFinalWindow() {
        let overlay = SpyOverlay()
        // through:36 — t36 instant-lock 직후까지만 본다. 그 이후엔 디바이스가
        // pruned되며 deviceUnseen 카운트다운이 새로 시작해 오버레이를 다시 열어
        // lastDeadline을 덮으므로(이 테스트의 관심사 아님) 잠금 시점에서 끊는다.
        let frames = replay(magnitude: 70, through: 36, overlay: overlay) { tick in
            tick <= 5 ? (rssi: -50, lastSeenTick: tick) : nil
        }

        // final window 진입 전(카운트다운 시작 t21 ~ t30)에는 show가 한 번도 안 불린다.
        #expect(frames.first { $0.showCount > 0 }!.tick == 31)
        #expect(frames.prefix(31).allSatisfy { $0.showCount == 0 })

        // final window(t31~t35)에서 show가 실제로 호출되고 deadline이 잡힌다.
        #expect(overlay.showCount >= 1)
        #expect(overlay.lastDeadline != nil)

        // deadline은 awaySince(t21) + grace(15) = t0 + 36초.
        let expectedDeadline = t0.addingTimeInterval(36)
        #expect(abs(overlay.lastDeadline!.timeIntervalSince(expectedDeadline)) < 0.001)
    }
}
