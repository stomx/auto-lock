import Testing
import Foundation
@testable import AutoLockCore

@Suite struct WakeDecisionTests {

    // 기준: threshold -70, wakeMargin 20 → wake 발화 경계는 -50.

    // wakeOnProximity off → doNothing
    @Test func wakeOffDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: false, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .doNothing)
    }

    // 이미 발화함 → doNothing
    @Test func alreadyFiredDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: true,
            isScreenLocked: true, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .doNothing)
    }

    // 화면 미잠금 → armForNextLock
    @Test func screenNotLockedArms() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: false, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .armForNextLock)
    }

    // 약신호(경계 미만) → doNothing
    @Test func weakSignalDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: -60, rssiThreshold: -70
        )
        #expect(a == .doNothing)
    }

    // best 없음 → doNothing
    @Test func noBestDoesNothing() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: nil, rssiThreshold: -70
        )
        #expect(a == .doNothing)
    }

    // 강신호 + autoUnlock on → attemptUnlock
    @Test func strongSignalAutoUnlock() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: true, alreadyFired: false,
            isScreenLocked: true, bestRssi: -40, rssiThreshold: -70
        )
        #expect(a == .attemptUnlock)
    }

    // 강신호 + autoUnlock off → wakeDisplay (정확히 경계값 -50도 발화)
    @Test func strongSignalWakeDisplay() {
        let a = WakeDecision.decide(
            wakeOnProximity: true, autoUnlock: false, alreadyFired: false,
            isScreenLocked: true, bestRssi: -50, rssiThreshold: -70
        )
        #expect(a == .wakeDisplay)
    }
}
