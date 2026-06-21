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

    /// 신호 끊김 허용은 더 이상 사용자 조정 항목이 아니라 15초 고정.
    @Test func graceIsFixedAtFifteenSeconds() {
        let s = makeSettings()
        #expect(s.gracePeriodSeconds == 15)
        #expect(s.gracePeriodSeconds == LockTuning.fixedGracePeriodSeconds)
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
        #expect(s.thresholdMagnitude == 75)
    }

    /// objectWillChange 직후 읽히는 threshold 값이 절대 범위 밖이 아니어야 한다
    /// (transient unclamped 방출 회귀 방지 — 관찰자는 항상 clamp된 값만 본다).
    @Test func observerNeverSeesUnclampedValue() {
        let s = makeSettings()
        var observed: [Int] = []
        let token = s.objectWillChange.sink { _ in observed.append(1) }
        s.thresholdMagnitude = 999    // 범위 밖
        token.cancel()

        #expect(observed.count == 1)
        #expect(s.thresholdMagnitude == 100)      // 항상 clamp된 값만 노출
    }
}
