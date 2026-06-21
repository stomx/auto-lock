import Testing
@testable import AutoLockCore

/// `BluetoothPowerState` is the domain enum that replaces CoreBluetooth's
/// `CBManagerState` at the Kit boundary. The raw-Int mapping mirrors the stable
/// `CBManagerState` case order so the Kit adapter can map without leaking the
/// framework type into Core.
@Suite struct BluetoothPowerStateTests {

    // CBManagerState 원시값(0~5)을 도메인 케이스로 정확히 매핑한다.
    @Test func mapsKnownRawStates() {
        #expect(BluetoothPowerState(rawState: 0) == .unknown)
        #expect(BluetoothPowerState(rawState: 1) == .resetting)
        #expect(BluetoothPowerState(rawState: 2) == .unsupported)
        #expect(BluetoothPowerState(rawState: 3) == .unauthorized)
        #expect(BluetoothPowerState(rawState: 4) == .poweredOff)
        #expect(BluetoothPowerState(rawState: 5) == .poweredOn)
    }

    // 알 수 없는/미래 원시값은 .unknown으로 안전하게 수렴한다.
    @Test func unknownRawStateFallsBackToUnknown() {
        #expect(BluetoothPowerState(rawState: 99) == .unknown)
        #expect(BluetoothPowerState(rawState: -1) == .unknown)
    }

    // poweredOn만 스캔 준비됨.
    @Test func onlyPoweredOnIsReady() {
        #expect(BluetoothPowerState.poweredOn.isReady)
        for s: BluetoothPowerState in [.unknown, .resetting, .unsupported, .unauthorized, .poweredOff] {
            #expect(!s.isReady)
        }
    }

    // 권한/꺼짐/미지원만 사용자 안내 대상.
    @Test func needsUserActionOnlyForActionableStates() {
        #expect(BluetoothPowerState.unauthorized.needsUserAction)
        #expect(BluetoothPowerState.poweredOff.needsUserAction)
        #expect(BluetoothPowerState.unsupported.needsUserAction)
        #expect(!BluetoothPowerState.unknown.needsUserAction)
        #expect(!BluetoothPowerState.resetting.needsUserAction)
        #expect(!BluetoothPowerState.poweredOn.needsUserAction)
    }
}
