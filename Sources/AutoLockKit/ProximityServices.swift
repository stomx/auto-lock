import Foundation
import AutoLockCore

/// 화면 잠금/잠금상태 조회. 실제 구현은 executable의 ScreenLocker 어댑터.
public protocol ScreenLocking {
    @discardableResult func lock() -> Bool
    func isScreenLocked() -> Bool
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
public protocol ProximityScanning: AnyObject {
    var devices: [UUID: DiscoveredDevice] { get }
    var gracePeriodProvider: () -> Int { get set }
    func startScanning()
    func stopScanning()
}
