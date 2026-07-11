import Foundation
import AutoLockKit
import AutoLockCore
import AutoLockSystemAdapters

/// 기존 enum/singleton 시스템 구현을 AutoLockKit 프로토콜에 맞추는 얇은 어댑터들.
/// 조립 루트(AutoLockApp)에서 ProximityController에 주입한다.

struct SystemScreenLocker: ScreenLocking {
    func lock() -> Bool { ScreenLocker.lock() }
    func isScreenLocked() -> Bool { ScreenLocker.isScreenLocked() }
}

struct SystemDisplayWaker: DisplayWaking {
    func wake() -> Bool { DisplayWaker.wake() }
}

struct SystemUnlockTrigger: UnlockTriggering {
    func attempt() -> UnlockOutcome { UnlockTrigger.attempt() }
}

@MainActor struct SystemOverlay: OverlayPresenting {
    func show(until deadline: Date) { CountdownOverlay.shared.show(until: deadline) }
    func hide() { CountdownOverlay.shared.hide() }
}
