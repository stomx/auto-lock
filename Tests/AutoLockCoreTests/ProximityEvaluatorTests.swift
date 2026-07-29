import Testing
import Foundation
@testable import AutoLockCore

@Suite struct ProximityEvaluatorTests {

    // Fixed reference clock so tests are deterministic (no wall-clock reads).
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let deviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// Build a snapshot with a visible device whose lastSeen is `age` seconds ago.
    private func snapshot(age: TimeInterval,
                          rssi: Double,
                          threshold: Int = -70,
                          definitiveAway: Int = -80,
                          grace: Int = 10,
                          countdown: Int = 5,
                          awaySince: Date? = nil) -> ProximitySnapshot {
        ProximitySnapshot(
            now: now,
            best: .init(id: deviceID, smoothedRssi: rssi, lastSeen: now.addingTimeInterval(-age)),
            rssiThreshold: threshold,
            definitiveAwayThreshold: definitiveAway,
            gracePeriodSeconds: grace,
            countdownSeconds: countdown,
            awaySince: awaySince
        )
    }

    // 마지막 신호 10초 + 카운트다운 5초가 지나면 총 15초에 잠근다.
    @Test func staleCountdownExpiryLocksAtCombinedDeadline() {
        let d = ProximityEvaluator.decide(snapshot(age: 15, rssi: -50))
        #expect(d.state == .away)
        #expect(d.action == .lock(reason: .signalStaleSeconds(15)))
        #expect(d.status == .locked(reason: .signalStaleSeconds(15)))
        #expect(d.awaySince == nil)
    }

    // 무신호 허용 10초 이후에는 마지막 광고 시각에 고정된 5초 카운트다운.
    @Test func staleCountdown() {
        let d = ProximityEvaluator.decide(snapshot(age: 12, rssi: -50))
        let lastSeen = now.addingTimeInterval(-12)
        #expect(d.state == .borderline)
        #expect(d.status == .countdown(reason: .signalStaleSeconds(12), secondsLeft: 3))
        #expect(d.action == .showOverlay(until: now.addingTimeInterval(3)))
        #expect(d.awaySince == lastSeen)
    }

    // #5: RSSI crashed below definitiveAway → instant crash lock
    @Test func signalCrashedInstantLock() {
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -95, definitiveAway: -90))
        #expect(d.action == .lock(reason: .signalCrashed))
        #expect(d.status == .instantLock(reason: .signalCrashed))
    }

    // #6: strong RSSI within range → near/watching
    @Test func nearWatching() {
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -50, threshold: -70))
        #expect(d.state == .near)
        #expect(d.status == .watching)
        #expect(d.action == .watching)
        #expect(d.awaySince == nil)
    }

    // #7: RSSI between thresholds → weak signal away countdown
    @Test func signalWeakCountdown() {
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -75, threshold: -70, definitiveAway: -80))
        #expect(d.state == .borderline)
        #expect(d.status == .countdown(reason: .signalWeak, secondsLeft: 5))
        #expect(d.action == .showOverlay(until: now.addingTimeInterval(5)))
    }

    // 기기를 한 번도 보지 못한 경우에도 10초 허용 + 5초 카운트다운.
    @Test func deviceUnseen() {
        let s = ProximitySnapshot(now: now, best: nil, rssiThreshold: -70,
                                  definitiveAwayThreshold: -80, gracePeriodSeconds: 10,
                                  countdownSeconds: 5, awaySince: nil)
        let d = ProximityEvaluator.decide(s)
        #expect(d.state == .borderline)
        #expect(d.status == .countdown(reason: .deviceUnseen, secondsLeft: 15))
        #expect(d.action == .hideOverlay)
        #expect(d.awaySince == now)
    }

    @Test func unseenShowsOverlayAfterTolerance() {
        let started = now.addingTimeInterval(-10)
        let s = ProximitySnapshot(now: now, best: nil, rssiThreshold: -70,
                                  definitiveAwayThreshold: -80, gracePeriodSeconds: 10,
                                  countdownSeconds: 5, awaySince: started)
        let d = ProximityEvaluator.decide(s)
        #expect(d.status == .countdown(reason: .deviceUnseen, secondsLeft: 5))
        #expect(d.action == .showOverlay(until: now.addingTimeInterval(5)))
    }

    // 약신호 카운트다운은 무신호 허용과 무관하게 설정된 5초만 사용한다.
    @Test func countdownExpiredLocks() {
        let started = now.addingTimeInterval(-5)
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -75, threshold: -70, awaySince: started))
        #expect(d.state == .away)
        #expect(d.action == .lock(reason: .signalWeak))
        #expect(d.status == .locked(reason: .signalWeak))
        #expect(d.awaySince == nil)
    }

    @Test func customCountdownDurationIsUsed() {
        let started = now.addingTimeInterval(-2)
        let d = ProximityEvaluator.decide(snapshot(
            age: 1,
            rssi: -75,
            threshold: -70,
            countdown: 8,
            awaySince: started
        ))
        #expect(d.state == .borderline)
        #expect(d.status == .countdown(reason: .signalWeak, secondsLeft: 6))
        #expect(d.action == .showOverlay(until: started.addingTimeInterval(8)))
    }
}
