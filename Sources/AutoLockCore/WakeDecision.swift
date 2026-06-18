import Foundation

public enum WakeAction: Equatable {
    case doNothing
    case armForNextLock   // 화면 미잠금 — 다음 잠금 사이클 위해 발화 플래그 해제
    case wakeDisplay
    case attemptUnlock
}

public enum WakeDecision {
    /// `ProximityController.maybeWakeDisplay()`의 분기 게이팅을 순수 함수로 추출.
    /// 동작은 기존 로직과 동일하다.
    public static func decide(
        wakeOnProximity: Bool,
        autoUnlock: Bool,
        alreadyFired: Bool,
        isScreenLocked: Bool,
        bestRssi: Double?,
        rssiThreshold: Int
    ) -> WakeAction {
        guard wakeOnProximity else { return .doNothing }
        // The screen-unlocked check MUST precede the alreadyFired check: once we
        // fired for a lock session and the user then unlocks, we have to re-arm
        // (`.armForNextLock`) so the *next* lock can wake/auto-unlock again.
        // Ordering alreadyFired first would latch forever — the second lock
        // session onward would silently never fire.
        guard isScreenLocked else { return .armForNextLock }
        guard !alreadyFired else { return .doNothing }
        guard let rssi = bestRssi, rssi >= Double(rssiThreshold) + LockTuning.wakeMarginDBm else { return .doNothing }
        return autoUnlock ? .attemptUnlock : .wakeDisplay
    }
}
