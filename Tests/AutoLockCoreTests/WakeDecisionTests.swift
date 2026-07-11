import Testing
import Foundation
@testable import AutoLockCore

@Suite struct WakeDecisionTests {

    // 기준: threshold -70, wakeMargin 10 → wake 발화 경계는 -60.

    // wakeOnProximity off → doNothing(proximityWakeOff)
    @Test func wakeOffDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: false, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .doNothing(.proximityWakeOff))
    }

    // 이미 발화함 → doNothing(alreadyFired)
    @Test func alreadyFiredDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: true,
            isScreenLocked: true, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .doNothing(.alreadyFired))
    }

    // 화면 미잠금 → armForNextLock
    @Test func screenNotLockedArms() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: false, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .armForNextLock)
    }

    // 약신호(경계 미만) → doNothing(signalBelowWakeLine). 사유에 rssi/line 동봉.
    @Test func weakSignalDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: -65, rssiThreshold: -70
        )
        #expect(a == .doNothing(.signalBelowWakeLine(rssi: -65, line: -60)))
    }

    // best 없음 → doNothing(noVisibleDevice)
    @Test func noBestDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: nil, rssiThreshold: -70
        )
        #expect(a == .doNothing(.noVisibleDevice))
    }

    // 강신호 + autoUnlock on → attemptUnlock
    @Test func strongSignalAutoUnlock() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: true, alreadyFired: false,
            isScreenLocked: true, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .attemptUnlock)
    }

    // 강신호 + autoUnlock off → wakeDisplay (정확히 경계값 -60도 발화)
    @Test func strongSignalWakeDisplay() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: -60, rssiThreshold: -70
        )
        #expect(a == .wakeDisplay)
    }

    // 경계 바로 아래(-61)는 발화하지 않는다 — 경계 정확성 회귀 방지.
    @Test func justBelowWakeLineDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: true, alreadyFired: false,
            isScreenLocked: true, bestRssi: -61, rssiThreshold: -70
        )
        #expect(a == .doNothing(.signalBelowWakeLine(rssi: -61, line: -60)))
    }

    // 이미 발화 후 사용자가 화면을 해제함 → 다음 잠금 세션을 위해 재무장.
    // (회귀: alreadyFired 가드가 isScreenLocked 가드보다 먼저면 영영 재무장 안 돼
    //  두 번째 잠금부터 wake/auto-unlock이 발화하지 않는다.)
    @Test func firedThenUnlockedRearms() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: true,
            isScreenLocked: false, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .armForNextLock)
    }

    // dedup 키(kind)는 동적 값이 달라도 같은 종류로 묶인다 — 매 틱 스킵 로그
    // 도배 방지의 근거.
    @Test func skipReasonKindIgnoresDynamicValues() {
        let a = WakeSkipReason.signalBelowWakeLine(rssi: -65, line: -60)
        let b = WakeSkipReason.signalBelowWakeLine(rssi: -80, line: -60)
        #expect(a.kind == b.kind)
        #expect(a != b)  // Equatable 자체는 값을 구분
    }

    @Test func belowWakeLineDescriptionIncludesObservedValues() {
        let reason = WakeSkipReason.signalBelowWakeLine(rssi: -65.9, line: -60.1)
        #expect(reason.logDescription == "signal-below-wakeline(rssi=-65 < line=-60)")
    }
}
