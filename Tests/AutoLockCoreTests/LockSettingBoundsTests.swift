import Testing
import Foundation
@testable import AutoLockCore

/// `LockSettingBounds` centralizes the valid ranges for the user-tunable lock
/// settings. `Settings` clamped only at init (loading from UserDefaults); a
/// runtime assignment of an out-of-range value (programmatic API, migration)
/// persisted unclamped, e.g. `gracePeriodSeconds = 0` → near-instant locking.
/// Extracting the clamps as pure functions lets the setters reuse them.
@Suite struct LockSettingBoundsTests {

    // 임계값 크기: 40~100.
    @Test func thresholdClampsLow() {
        #expect(LockSettingBounds.clampThresholdMagnitude(10) == 40)
    }
    @Test func thresholdClampsHigh() {
        #expect(LockSettingBounds.clampThresholdMagnitude(250) == 100)
    }
    @Test func thresholdPassesInRange() {
        #expect(LockSettingBounds.clampThresholdMagnitude(75) == 75)
    }
    @Test func thresholdBoundsAreInclusive() {
        #expect(LockSettingBounds.clampThresholdMagnitude(40) == 40)
        #expect(LockSettingBounds.clampThresholdMagnitude(100) == 100)
    }

    // 신호 끊김 허용: 15~maxGracePeriodSeconds(60).
    @Test func graceClampsLow() {
        #expect(LockSettingBounds.clampGracePeriodSeconds(0) == 15)
    }
    @Test func graceClampsHigh() {
        #expect(LockSettingBounds.clampGracePeriodSeconds(120) == LockTuning.maxGracePeriodSeconds)
    }
    @Test func gracePassesInRange() {
        #expect(LockSettingBounds.clampGracePeriodSeconds(30) == 30)
    }
    @Test func graceBoundsAreInclusive() {
        #expect(LockSettingBounds.clampGracePeriodSeconds(15) == 15)
        #expect(LockSettingBounds.clampGracePeriodSeconds(LockTuning.maxGracePeriodSeconds) == LockTuning.maxGracePeriodSeconds)
    }

    // 기본 임계값은 README 권장 범위(-75~-85dBm)의 중앙인 -80dBm(magnitude 80).
    // 첫 등록 직후 합리적으로 동작하도록. (과거 100=−100dBm은 거의 안 잠겨 문서와 어긋났다.)
    @Test func defaultThresholdMatchesRecommendedRange() {
        #expect(LockSettingBounds.defaultThresholdMagnitude == 80)
        // 기본값은 당연히 유효 범위 안이어야 한다.
        #expect(LockSettingBounds.clampThresholdMagnitude(LockSettingBounds.defaultThresholdMagnitude)
                == LockSettingBounds.defaultThresholdMagnitude)
    }
}
