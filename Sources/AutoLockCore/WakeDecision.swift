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
        guard !alreadyFired else { return .doNothing }
        guard isScreenLocked else { return .armForNextLock }
        guard let rssi = bestRssi, rssi >= Double(rssiThreshold) + LockTuning.wakeMarginDBm else { return .doNothing }
        return autoUnlock ? .attemptUnlock : .wakeDisplay
    }
}
