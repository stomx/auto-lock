import Foundation
import AutoLockCore

/// 화면 잠금/잠금상태 조회. 실제 구현은 executable의 ScreenLocker 어댑터.
public protocol ScreenLocking {
    @discardableResult func lock() -> Bool
    func isScreenLocked() -> Bool
    func screenLockState() -> ScreenLockState
}

public extension ScreenLocking {
    func screenLockState() -> ScreenLockState {
        isScreenLocked() ? .locked : .unlocked
    }
}

/// 디스플레이 깨우기. 실제 구현은 executable의 DisplayWaker 어댑터.
public protocol DisplayWaking {
    @discardableResult func wake() -> Bool
}

/// 자동 잠금 해제 시도. 실제 구현은 executable의 UnlockTrigger 어댑터.
public protocol UnlockTriggering {
    func attempt() -> UnlockOutcome
}

/// 카운트다운 오버레이 표시/숨김.
@MainActor public protocol OverlayPresenting {
    func show(until deadline: Date)
    func hide()
}

/// BLE 스캐너 추상화. BLEScanner가 conform한다.
/// MainActor 격리: 실제 구현(BLEScanner)이 CoreBluetooth queue:.main에서 동작하고
/// Settings(MainActor)를 읽으므로, 스캐너 계약 전체를 main actor로 맞춘다.
@MainActor
public protocol ProximityScanning: AnyObject {
    var devices: [UUID: DiscoveredDevice] { get }
    var gracePeriodProvider: @MainActor () -> Int { get set }
    var countdownPeriodProvider: @MainActor () -> Int { get set }
    func startScanning()
    func stopScanning()
}
