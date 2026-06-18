import Testing
import Foundation
@testable import AutoLockCore

/// `RssiSmoother`는 BLEScanner에 인라인돼 있던 EWMA 평활화와 per-device 상태
/// 보관을 순수 타입으로 추출한 것이다. CoreBluetooth 없이 테스트할 수 있고,
/// prune 시 평활 상태가 함께 정리되어(누수 방지) 기기 사전과 동기화된다.
@Suite struct RssiSmootherTests {
    private let a = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let b = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // 1. 첫 샘플은 평활화 없이 그대로 반환된다(이전 상태가 없으므로).
    @Test func firstSampleReturnsRaw() {
        var smoother = RssiSmoother()
        let v = smoother.update(id: a, rawRssi: -60)
        #expect(v == -60)
    }

    // 2. 두 번째 샘플은 EWMA로 블렌딩된다: prev*(1-f) + raw*f, f=0.3.
    @Test func secondSampleBlends() {
        var smoother = RssiSmoother()
        _ = smoother.update(id: a, rawRssi: -60)           // prev = -60
        let v = smoother.update(id: a, rawRssi: -80)        // -60*0.7 + -80*0.3 = -66
        #expect(abs(v - (-66)) < 1e-9)
    }

    // 3. 서로 다른 기기는 독립된 평활 상태를 가진다.
    @Test func perDeviceStateIsIndependent() {
        var smoother = RssiSmoother()
        _ = smoother.update(id: a, rawRssi: -50)
        let vb = smoother.update(id: b, rawRssi: -90)        // b의 첫 샘플 → 그대로
        #expect(vb == -90)
        let va = smoother.update(id: a, rawRssi: -50)        // a는 -50 유지
        #expect(abs(va - (-50)) < 1e-9)
    }

    // 4. prune은 keeping 집합에 없는 기기의 평활 상태를 제거한다(누수 방지).
    @Test func pruneRemovesAbsentState() {
        var smoother = RssiSmoother()
        _ = smoother.update(id: a, rawRssi: -60)
        _ = smoother.update(id: b, rawRssi: -70)
        #expect(smoother.trackedCount == 2)

        smoother.prune(keeping: [a])
        #expect(smoother.trackedCount == 1)

        // b가 제거됐으므로 다시 등장하면 첫 샘플로 취급되어 평활화 없이 그대로.
        let vb = smoother.update(id: b, rawRssi: -40)
        #expect(vb == -40)
    }

    // 5. prune 후에도 유지된 기기는 평활 상태가 보존된다.
    @Test func prunePreservesKeptState() {
        var smoother = RssiSmoother()
        _ = smoother.update(id: a, rawRssi: -60)
        smoother.prune(keeping: [a])
        let va = smoother.update(id: a, rawRssi: -80)        // 상태 보존 → 블렌딩
        #expect(abs(va - (-66)) < 1e-9)
    }

    // 6. 빈 keeping 집합으로 prune하면 모든 상태가 비워진다.
    @Test func pruneEmptyClearsAll() {
        var smoother = RssiSmoother()
        _ = smoother.update(id: a, rawRssi: -60)
        _ = smoother.update(id: b, rawRssi: -70)
        smoother.prune(keeping: [])
        #expect(smoother.trackedCount == 0)
    }
}
