import Foundation

/// 자동 잠금 해제 시도 결과. UnlockTrigger.Result에서 이동해 공유 라이브러리에 둔다.
public enum UnlockOutcome: Equatable {
    case unlocked
    case noPassword
    case noAccessibility
    case dispatched
}
