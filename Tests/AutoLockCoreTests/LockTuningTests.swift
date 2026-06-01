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

    // #11: Reachability proof — the pruner must evict LATER than the absence
    // (instant-lock) point for every supported grace value, otherwise the
    // stale/absence branches in ProximityEvaluator are dead code.
    @Test func pruneAlwaysOutlivesAbsencePoint() {
        for grace in 15...60 {
            let absence = Double(grace) * LockTuning.absenceMultiplier
            let prune = LockTuning.pruneAfterSeconds(gracePeriodSeconds: grace)
            #expect(
                prune > absence,
                "prune(\(prune)) must exceed absence(\(absence)) at grace=\(grace) so the device survives until the instant-lock decision"
            )
        }
    }
}
