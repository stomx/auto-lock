import Testing
import Foundation
@testable import AutoLockCore

@Suite struct LockTuningTests {

    // #1: grace=15 → 15*2 + 2 = 32
    @Test func pruneAfterSecondsMinGrace() {
        #expect(LockTuning.pruneAfterSeconds(gracePeriodSeconds: 15) == 32.0)
    }

    // #2: grace=60 → 60*2 + 2 = 122
    @Test func pruneAfterSecondsMaxGrace() {
        #expect(LockTuning.pruneAfterSeconds(gracePeriodSeconds: 60) == 122.0)
    }

    // 신호 끊김 허용은 더 이상 사용자 조정 항목이 아니라 15초 고정.
    @Test func fixedGraceIsFifteenSeconds() {
        #expect(LockTuning.fixedGracePeriodSeconds == 15)
    }

    // 고정 grace에서도 reachability 불변식이 성립해야 한다(pruner가 absence 이후 evict).
    @Test func fixedGracePruneOutlivesAbsence() {
        let grace = LockTuning.fixedGracePeriodSeconds
        let absence = Double(grace) * LockTuning.absenceMultiplier
        let prune = LockTuning.pruneAfterSeconds(gracePeriodSeconds: grace)
        #expect(prune > absence)
    }

    // #11: Reachability proof — the pruner must evict LATER than the absence
    // (instant-lock) point across the historical grace span, otherwise the
    // stale/absence branches in ProximityEvaluator are dead code.
    @Test func pruneAlwaysOutlivesAbsencePoint() {
        for grace in 10...60 {
            let absence = Double(grace) * LockTuning.absenceMultiplier
            let prune = LockTuning.pruneAfterSeconds(gracePeriodSeconds: grace)
            #expect(
                prune > absence,
                "prune(\(prune)) must exceed absence(\(absence)) at grace=\(grace) so the device survives until the instant-lock decision"
            )
        }
    }
}
