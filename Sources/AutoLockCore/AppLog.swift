import Foundation
import os

/// 통합 로깅(Unified Logging) 진입점. 기존 `NSLog`를 대체한다.
///
/// `NSLog`는 릴리스 빌드/GUI 앱에서 `log show`·Console 에 신뢰성 있게 실리지
/// 않는다(특히 자식 stderr 가 통합 로깅으로 흐르지 않는 환경). 그래서
/// "자동 잠금/해제가 왜 발화하지 않았는가"를 사후에 추적할 수 없었다.
/// `os.Logger` 는 subsystem/category 가 붙은 채 항상 통합 로깅에 기록되므로
/// 아래처럼 카테고리별로 필터링해 읽을 수 있다:
///
///   log show --last 30m --predicate 'subsystem == "com.local.autolock"' --info
///   log stream         --predicate 'subsystem == "com.local.autolock"' --level info
///
/// `os` 는 모든 Apple 플랫폼이 제공하는 시스템 모듈이라 AutoLockCore 의
/// "Foundation only(외부 의존 없음)" 원칙을 깨지 않는다. 도메인 순수 결정
/// 함수들은 여전히 로깅하지 않으며, 부수효과를 내는 컨트롤러/어댑터만 쓴다.
///
/// 저장용량 정책 — 레벨을 의도적으로 가른다:
///  - 정상 동작(발화/스킵/잠금 성공)은 `.info`. 통합 로깅에서 .info 는 평소
///    디스크에 영구 저장되지 않고 메모리 버퍼에만 머문다. 그래서 상시 운영
///    중에는 저장용량을 사실상 차지하지 않으면서도, 문제를 추적할 땐
///    `log stream`(실시간) 또는 `log show --info`(최근 버퍼)로 끌어낼 수 있다.
///  - 실패(이벤트소스 없음, 잠금 호출 실패 등)만 `.error`. 디스크에 보존돼
///    사후에 `log show`(--info 없이도)로 바로 보인다. 실패는 드물어 누적량이
///    미미하다.
/// 통합 로깅 자체의 총량 상한·롤링은 macOS 가 관리하므로 앱이 디스크를 무한
/// 점유할 수 없다.
public enum AppLog {
    /// 모든 카테고리가 공유하는 subsystem. 번들 ID 와 일치시켜 Console 에서
    /// 프로세스 단위로 묶어 보기 좋게 한다.
    public static let subsystem = "com.local.autolock"

    /// 근접 상태머신(평가/잠금 발화). `ProximityController` 가 쓴다.
    public static let proximity = Logger(subsystem: subsystem, category: "proximity")
    /// 화면 깨우기 / 자동 잠금 해제 발화 경로.
    public static let wake = Logger(subsystem: subsystem, category: "wake")
    /// 화면 잠금 실행(ScreenLocker) 및 권한/키체인 등 시스템 호출.
    public static let system = Logger(subsystem: subsystem, category: "system")
}
