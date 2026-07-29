import Testing
import Foundation
@testable import AutoLockCore

@Suite struct LockTuningTests {

    // 기본 10초 무신호 + 5초 카운트다운 + 2초 프루닝 여유 = 17초.
    @Test func pruneAfterDefaultTiming() {
        #expect(LockTuning.pruneAfterSeconds(
            gracePeriodSeconds: 10,
            countdownSeconds: 5
        ) == 17.0)
    }

    @Test func signalLossLockPointAddsToleranceAndCountdown() {
        #expect(LockTuning.signalLossLockPointSeconds(
            gracePeriodSeconds: 10,
            countdownSeconds: 5
        ) == 15.0)
    }

    // 프루너는 모든 허용 설정 조합에서 실제 잠금 시점보다 늦게 동작해야 한다.
    @Test func pruneAlwaysOutlivesSignalLossLockPoint() {
        for grace in stride(
            from: LockSettingBounds.gracePeriodRange.lowerBound,
            through: LockSettingBounds.gracePeriodRange.upperBound,
            by: LockSettingBounds.gracePeriodStep
        ) {
            for countdown in LockSettingBounds.countdownRange {
                let lockPoint = LockTuning.signalLossLockPointSeconds(
                    gracePeriodSeconds: grace,
                    countdownSeconds: countdown
                )
                let prune = LockTuning.pruneAfterSeconds(
                    gracePeriodSeconds: grace,
                    countdownSeconds: countdown
                )
                #expect(
                    prune > lockPoint,
                    "prune(\(prune)) must exceed lockPoint(\(lockPoint)) at grace=\(grace), countdown=\(countdown)"
                )
            }
        }
    }
}
