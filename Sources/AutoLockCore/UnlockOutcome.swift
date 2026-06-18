import Foundation

/// 자동 잠금 해제 시도 결과. UnlockTrigger.Result에서 이동해 공유 라이브러리에 둔다.
public enum UnlockOutcome: Equatable {
    case unlocked
    case noPassword
    case noAccessibility
    case dispatched
    /// The system refused to vend a `CGEventSource`, so no keystrokes could be
    /// synthesized. Previously this failure was swallowed inside an async block
    /// while `attempt()` had already optimistically reported `.dispatched`.
    case eventSourceUnavailable
}
