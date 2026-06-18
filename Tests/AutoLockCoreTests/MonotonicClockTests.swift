import Testing
import Foundation
@testable import AutoLockCore

/// `MonotonicClock` supplies the timeline for all proximity timing. The defect
/// it fixes: every age/deadline was derived from `Date()` (wall clock), so an
/// NTP correction or manual clock change would make a still-present device look
/// long-absent (false instant-lock) or a departed device look fresh forever.
/// A monotonic source removes that coupling.
@Suite struct MonotonicClockTests {

    // 1. 단조성: 연속 호출은 절대 과거로 가지 않는다.
    @Test func neverGoesBackward() {
        var prev = MonotonicClock.now()
        for _ in 0..<1000 {
            let next = MonotonicClock.now()
            #expect(next >= prev)
            prev = next
        }
    }

    // 2. 두 인스턴트의 차이는 음수가 될 수 없다(age 계산이 음수로 새지 않음).
    @Test func differenceIsNonNegative() {
        let a = MonotonicClock.now()
        let b = MonotonicClock.now()
        #expect(b.timeIntervalSince(a) >= 0)
    }

    // 3. 도메인이 기대하는 형태 — Date 인스턴트로 노출되어 ProximitySnapshot에
    //    그대로 들어갈 수 있다(차이값만 의미 있음, 달력 날짜로 해석 금지).
    @Test func producesUsableInstant() {
        let now = MonotonicClock.now()
        // 어떤 기준점이든 유효한 Date여야 한다.
        #expect(now.timeIntervalSinceReferenceDate.isFinite)
    }
}
