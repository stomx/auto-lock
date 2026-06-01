import Testing
import Foundation
@testable import AutoLockCore

@Suite struct BestDeviceSelectorTests {

    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
    private let idC = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000000")!

    private func device(_ id: UUID, rssi: Double) -> DiscoveredDevice {
        DiscoveredDevice(id: id, name: "dev", smoothedRssi: rssi, lastSeen: now)
    }

    // 빈 맵 → nil
    @Test func emptyDevicesReturnsNil() {
        #expect(BestDeviceSelector.select(trackedIDs: [idA], from: [:]) == nil)
    }

    // 추적 ID가 맵에 없음 → nil
    @Test func trackedNotVisibleReturnsNil() {
        let devices = [idB: device(idB, rssi: -50)]
        #expect(BestDeviceSelector.select(trackedIDs: [idA], from: devices) == nil)
    }

    // 단일 기기 → 그 기기
    @Test func singleVisibleDevice() {
        let devices = [idA: device(idA, rssi: -55)]
        let best = BestDeviceSelector.select(trackedIDs: [idA], from: devices)
        #expect(best?.id == idA)
        #expect(best?.smoothedRssi == -55)
        #expect(best?.lastSeen == now)
    }

    // 다중 기기 중 RSSI 최대값 선택 (더 강한 = 0에 가까운 음수)
    @Test func picksStrongestRssi() {
        let devices = [
            idA: device(idA, rssi: -80),
            idB: device(idB, rssi: -40),
            idC: device(idC, rssi: -60),
        ]
        let best = BestDeviceSelector.select(trackedIDs: [idA, idB, idC], from: devices)
        #expect(best?.id == idB)
        #expect(best?.smoothedRssi == -40)
    }

    // 추적 ID 일부만 보일 때 보이는 것 중에서 선택
    @Test func ignoresUntrackedAndInvisible() {
        let devices = [
            idA: device(idA, rssi: -70),
            idC: device(idC, rssi: -30),   // 추적 대상 아님
        ]
        let best = BestDeviceSelector.select(trackedIDs: [idA, idB], from: devices)
        #expect(best?.id == idA)
    }
}
