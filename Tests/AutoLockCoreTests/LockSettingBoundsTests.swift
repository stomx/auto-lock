import Testing
import Foundation
@testable import AutoLockCore

/// `LockSettingBounds` centralizes normalization for every user-tunable lock
/// setting so runtime values and persisted values share one contract.
@Suite struct LockSettingBoundsTests {

    // 임계값 크기: 40~100, 5 dBm 단위.
    @Test func thresholdClampsLow() {
        #expect(LockSettingBounds.clampThresholdMagnitude(10) == 40)
    }
    @Test func thresholdClampsHigh() {
        #expect(LockSettingBounds.clampThresholdMagnitude(250) == 100)
    }
    @Test func thresholdPassesInRange() {
        #expect(LockSettingBounds.clampThresholdMagnitude(75) == 75)
    }
    @Test func thresholdSnapsToFiveDBmStep() {
        #expect(LockSettingBounds.clampThresholdMagnitude(72) == 70)
        #expect(LockSettingBounds.clampThresholdMagnitude(73) == 75)
    }
    @Test func thresholdBoundsAreInclusive() {
        #expect(LockSettingBounds.clampThresholdMagnitude(40) == 40)
        #expect(LockSettingBounds.clampThresholdMagnitude(100) == 100)
    }

    // 무신호 허용: 5~60초, 5초 단위, 기본 10초.
    @Test func graceClampsAndSnaps() {
        #expect(LockSettingBounds.clampGracePeriodSeconds(0) == 5)
        #expect(LockSettingBounds.clampGracePeriodSeconds(62) == 60)
        #expect(LockSettingBounds.clampGracePeriodSeconds(12) == 10)
        #expect(LockSettingBounds.clampGracePeriodSeconds(13) == 15)
    }

    // 카운트다운: 1~30초, 1초 단위, 기본 5초.
    @Test func countdownClamps() {
        #expect(LockSettingBounds.clampCountdownSeconds(0) == 1)
        #expect(LockSettingBounds.clampCountdownSeconds(31) == 30)
        #expect(LockSettingBounds.clampCountdownSeconds(7) == 7)
    }

    // 기본 임계값은 README 권장 범위(-75~-85dBm)의 중앙인 -80dBm(magnitude 80).
    // 첫 등록 직후 합리적으로 동작하도록. (과거 100=−100dBm은 거의 안 잠겨 문서와 어긋났다.)
    @Test func defaultThresholdMatchesRecommendedRange() {
        #expect(LockSettingBounds.defaultThresholdMagnitude == 80)
        // 기본값은 당연히 유효 범위 안이어야 한다.
        #expect(LockSettingBounds.clampThresholdMagnitude(LockSettingBounds.defaultThresholdMagnitude)
                == LockSettingBounds.defaultThresholdMagnitude)
    }

    @Test func timingDefaultsMatchProductContract() {
        #expect(LockSettingBounds.defaultGracePeriodSeconds == 10)
        #expect(LockSettingBounds.defaultCountdownSeconds == 5)
    }
}
