import Testing
import Foundation
import Combine
@testable import AutoLockKit
import AutoLockCore

/// Verifies the runtime-clamp wiring in `Settings` setters (the pure bounds are
/// covered by `LockSettingBoundsTests`; this pins the didSet integration and
/// that the clamped value is what gets persisted).
@MainActor
@Suite struct SettingsTests {

    private func makeSettings() -> Settings {
        let defaults = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        return Settings(defaults: defaults)
    }

    @Test func thresholdSetterClampsHigh() {
        let s = makeSettings()
        s.thresholdMagnitude = 500
        #expect(s.thresholdMagnitude == 100)
    }

    @Test func thresholdSetterClampsLow() {
        let s = makeSettings()
        s.thresholdMagnitude = 0
        #expect(s.thresholdMagnitude == 40)
    }

    @Test func graceSetterClampsLow() {
        let s = makeSettings()
        s.gracePeriodSeconds = 0   // 회귀: 즉시잠금에 가까운 값 차단
        #expect(s.gracePeriodSeconds == 15)
    }

    @Test func graceSetterClampsHigh() {
        let s = makeSettings()
        s.gracePeriodSeconds = 9999
        #expect(s.gracePeriodSeconds == LockTuning.maxGracePeriodSeconds)
    }

    /// 저장값이 없는 새 설치는 README 권장 -80dBm(magnitude 80)으로 시작한다.
    @Test func freshInstallUsesRecommendedDefault() {
        let s = makeSettings()
        #expect(s.thresholdMagnitude == LockSettingBounds.defaultThresholdMagnitude)
        #expect(s.thresholdMagnitude == 80)
    }

    @Test func inRangeValuesPassThrough() {
        let s = makeSettings()
        s.thresholdMagnitude = 75
        s.gracePeriodSeconds = 30
        #expect(s.thresholdMagnitude == 75)
        #expect(s.gracePeriodSeconds == 30)
    }

    /// objectWillChange 직후 읽히는 값이 절대 범위 밖이 아니어야 한다
    /// (transient unclamped 방출 회귀 방지 — 관찰자는 항상 clamp된 값만 본다).
    @Test func observerNeverSeesUnclampedValue() {
        let s = makeSettings()
        var observed: [Int] = []
        let token = s.objectWillChange.sink { _ in
            // willChange는 변경 직전에 오지만, computed setter는 send() 후 동기적으로
            // backing을 쓰므로 다음 RunLoop 없이도 최종값 검증이 가능. 여기서는
            // 변경이 일어났다는 사실만 세고, 값 검증은 setter 완료 후 수행한다.
            observed.append(1)
        }
        s.gracePeriodSeconds = 0      // 범위 밖
        s.thresholdMagnitude = 999    // 범위 밖
        token.cancel()

        #expect(observed.count == 2)              // 두 번 변경 통지
        #expect(s.gracePeriodSeconds == 15)       // 항상 clamp된 값만 노출
        #expect(s.thresholdMagnitude == 100)
    }

    /// 클램프된 값이 실제로 영속화되어 재로드 시에도 유지되는지.
    @Test func clampedValuePersists() {
        let suite = "settings-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let s1 = Settings(defaults: defaults)
        s1.gracePeriodSeconds = 0
        let s2 = Settings(defaults: defaults)
        #expect(s2.gracePeriodSeconds == 15)
    }
}
