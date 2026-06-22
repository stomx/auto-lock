import Foundation

/// 깨우기/자동해제를 발화하지 않은 이유. `.doNothing` 한 가지로 뭉뚱그리면
/// "PC 앞에 왔는데 왜 안 풀렸나"를 사후에 구분할 수 없어, 각 스킵 경로를
/// 분리해 로깅 가능하게 한다.
public enum WakeSkipReason: Equatable {
    case proximityWakeOff        // '근접 시 화면 깨우기' 토글이 꺼짐
    case alreadyFired            // 이 잠금 세션에서 이미 발화함
    case noVisibleDevice         // 추적 기기가 스캔에 안 보임(bestRssi == nil)
    case signalBelowWakeLine(rssi: Double, line: Double)  // 신호가 발동선 미달

    /// 로그용 ASCII 식별자(동적 값 포함).
    public var logDescription: String {
        switch self {
        case .proximityWakeOff:    return "wake-toggle-off"
        case .alreadyFired:        return "already-fired"
        case .noVisibleDevice:     return "no-visible-device"
        case .signalBelowWakeLine(let rssi, let line):
            return "signal-below-wakeline(rssi=\(Int(rssi)) < line=\(Int(line)))"
        }
    }

    /// 동적 값을 뺀 사유 종류 태그. 매 틱(1초) 반복되는 스킵 로그를 "종류가
    /// 바뀔 때만" 남기도록 중복 제거(dedup)하는 키로 쓴다. signalBelowWakeLine 의
    /// rssi 가 매 틱 달라져도 같은 종류로 묶여 도배를 막는다.
    public var kind: String {
        switch self {
        case .proximityWakeOff:    return "wake-toggle-off"
        case .alreadyFired:        return "already-fired"
        case .noVisibleDevice:     return "no-visible-device"
        case .signalBelowWakeLine: return "signal-below-wakeline"
        }
    }
}

public enum WakeAction: Equatable {
    case doNothing(WakeSkipReason)
    case armForNextLock   // 화면 미잠금 — 다음 잠금 사이클 위해 발화 플래그 해제
    case wakeDisplay
    case attemptUnlock
}

public enum WakeDecision {
    /// `ProximityController.maybeWakeDisplay()`의 분기 게이팅을 순수 함수로 추출.
    /// 발화하지 않는 경우 그 사유(`WakeSkipReason`)를 함께 돌려줘 컨트롤러가
    /// 로깅할 수 있게 한다.
    public static func decide(
        wakeOnProximity: Bool,
        autoUnlock: Bool,
        alreadyFired: Bool,
        isScreenLocked: Bool,
        bestRssi: Double?,
        rssiThreshold: Int
    ) -> WakeAction {
        guard wakeOnProximity else { return .doNothing(.proximityWakeOff) }
        // The screen-unlocked check MUST precede the alreadyFired check: once we
        // fired for a lock session and the user then unlocks, we have to re-arm
        // (`.armForNextLock`) so the *next* lock can wake/auto-unlock again.
        // Ordering alreadyFired first would latch forever — the second lock
        // session onward would silently never fire.
        guard isScreenLocked else { return .armForNextLock }
        guard !alreadyFired else { return .doNothing(.alreadyFired) }
        let wakeLine = Double(rssiThreshold) + LockTuning.wakeMarginDBm
        guard let rssi = bestRssi else { return .doNothing(.noVisibleDevice) }
        guard rssi >= wakeLine else {
            return .doNothing(.signalBelowWakeLine(rssi: rssi, line: wakeLine))
        }
        return autoUnlock ? .attemptUnlock : .wakeDisplay
    }
}
