# Changelog

이 프로젝트의 변경 사항을 기록합니다. 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를
따르고, 버전 번호는 [Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

## [0.4.0] — 2026-06-20

### Added
- **GitHub Releases 기반 자동 업데이트.** 앱 시작 시(및 메뉴 버전 클릭 시) 최신
  릴리스를 확인하고, 새 버전이 있으면 메뉴에 업데이트 버튼을 노출합니다. 누르면
  `arm64` DMG를 내려받아 **`SHA256SUMS.txt`와 대조 검증(fail-closed)** 후 디스크
  이미지를 엽니다. 체크섬 자산 누락·엔트리 누락·불일치·다운로드 실패는 모두
  업데이트를 중단합니다. ad-hoc 서명 빌드라 앱 자가교체는 하지 않고 "다운로드·
  검증·열기"까지만 자동화하며, 마지막 드래그 설치는 사용자가 수행합니다.
  - 결정 로직은 전부 `AutoLockCore` 순수 타입으로 분리: `SemanticVersion`(버전
    파싱·비교), `ReleaseInfo`/`UpdateCheck`(릴리스 파싱·다운그레이드 거부),
    `ChecksumVerifier`(fail-closed 검증). 컨트롤러(`UpdateController`)는
    `@MainActor` 상태머신으로 재진입 가드를 두고, 시스템 경계(GitHub API·
    URLSession 다운로드·NSWorkspace 열기)는 조립 루트에서 주입합니다.
  - `diagnose update` 서브커맨드 — 제품 코드 그대로 조회→비교→다운로드→검증을
    E2E 점검(`--current`로 가능 경로 강제, `--feed`로 픽스처 주입, `--download`/
    `--open` 단계 선택).

### Changed
- **신호 끊김 허용 시간을 10초로 고정**하고 사용자 조정 슬라이더를 제거했습니다.
  이전에는 15~60초 범위에서 조정 가능했으나, 고정 상수
  (`LockTuning.fixedGracePeriodSeconds`)로 단순화했습니다. `Settings`의 grace
  영속화·클램프 로직이 제거되고, plumbing(컨트롤러·BLE 프루너)은 그대로 이 값을
  읽습니다.

## [0.3.1] — 2026-06-18

v0.3.0(3계층 아키텍처 + 테스트 인프라 도입은 이미 0.3.0 범위) **이후** 코드
리뷰(독립 에이전트 교차검증)에서 발견한 결함을 TDD로 수정. 추가 도메인 로직을
`AutoLockCore`의 순수 타입으로 추출해 swift-testing으로 커버(테스트 37 → 104건).

### Added
- `MonotonicClock` — 근접 타이밍을 시스템 가동시간 기준으로 측정해 NTP 보정·
  수동 시간 변경에도 잠금/카운트다운이 오작동하지 않음.
- 잠금 실패 상태(`ControllerStatus.lockFailed`) — `SACLockScreenImmediate`가
  실패하면 "잠김"으로 위장하지 않고 메뉴에 표시하며 다음 주기에 재시도.
- 위험 로직을 검증 가능한 순수 타입으로 추출: `RssiSmoother`, `UnlockPreflight`,
  `UnlockFollowup`, `KeychainACLPolicy`, `ScanPolicy`, `DeviceNameResolver`,
  `LockSettingBounds`, `CStringSafe`.

### Fixed
- **자동 시작 시 토글 OFF인데 BLE 스캔이 켜지던 문제** — 스캔 요청 상태를 분리해
  꺼져 있으면 재개하지 않음(배터리/프라이버시).
- **기능을 껐다 켜면 오래된 신호로 즉시 잠기던 문제** — 스캔 중지 시 발견 목록을
  비우고, 중지 후 도착하는 지연 콜백을 무시.
- **근접 복귀 자동 해제 후 두 번째 잠금부터 화면이 안 깨던 문제** — 잠금 해제 시
  다음 주기를 위해 재무장.
- **자동 해제 실패 시 화면도 안 켜지던 문제** — 실패하면 최소한 화면을 깨워 수동
  인증이 가능하도록 fallback.
- **실제 기기 이름이 "Unknown"에 가려 픽커에서 안 보이던 문제** — 이름 해석 로직
  교정(nil/빈값/"Unknown"을 실명 후보에서 제외).
- BLE 신호 평활화(EWMA) 상태가 기기 제거 후에도 남던 메모리 누수.
- 토글 OFF/디바이스 삭제 후에도 메뉴에 이전 RSSI가 남던 문제.
- 설정값이 슬라이더 범위 밖으로 들어오면 그대로 저장되던 문제 — 항상 클램프.
- Keychain ACL 빌드 실패를 무시하던 문제 — 실패를 판정·로깅하고 무프롬프트
  ACL이 불완전하면 기본 ACL로 안전하게 폴백.
- `dlerror()`가 NULL을 반환할 때의 미정의 동작(잠재 크래시).

### Changed
- 거리 임계값 기본값을 -100 dBm → **-80 dBm**로 변경(권장 -75~-85의 중앙). 첫
  등록 직후 별도 조정 없이 합리적으로 동작.
- Swift 6 strict concurrency 정합 — UI/BLE/설정 상태를 main actor로 격리해
  데이터 레이스 경고 해소.
- `MenuView.swift`(896줄)를 `DesignSystem` / `DevicePickerView` /
  `PasswordSheetView`로 분할.

## [0.2.1] — 2026-05-28

### Added
- 메뉴 하단에 빌드 버전 표시 (`v0.2.1 (build 3)`).
- `docs/PROJECT_STATUS.md` — 프로젝트 현황과 후속 과제 정리.
- `Sources/AutoLock/LockTuning.swift` — 도메인 튜닝 상수(8개)를 단일 소스로 통합.

### Changed
- 화면 깨우기/자동 해제 트리거에 잠금 임계값 대비 **+20 dBm 마진** 적용 — 옆방
  신호로 인한 화면 켜짐 오작동 방지.
- 컨트롤러 상태를 한국어 문자열에서 `LockReason` / `ControllerStatus` enum으로
  분리. UI 레이어에서 한국어 매핑 — i18n 가능 구조.
- 매직 넘버(`0.3` smoothing, `0.6s` keystroke delay, `1.0s` evaluate, `0.05s` overlay
  tick, grace 배수, wake margin 등)를 `LockTuning`으로 명명.
- 파일명 정합: `LockController.swift` → `ScreenLocker.swift`.

### Removed
- 미사용 `Settings.lockThreshold` / `unlockThreshold` 별칭.
- `PasswordWindow.ASCIIOnlyWindow`의 no-op `performKeyEquivalent` 오버라이드.

## [0.2.0] — 2026-05-28

### Added
- **자동 잠금 해제 (실험적)**: 근접 복귀 시 저장된 로그인 암호를 잠금 화면에 자동
  입력하는 기능. 메뉴 → "근접 시 자동 잠금 해제" 토글로 활성화. macOS Keychain에
  암호 저장, 접근성(Accessibility) 권한 필요.
  - 잠금 화면이 외부 키 이벤트를 차단하는 일부 macOS 환경에서는 화면 깨우기까지만
    동작합니다 (Apple Watch Auto Unlock과 병행 권장).
- **앱 아이콘**: 자물쇠 + 표류하는 신호 점 컨셉의 라임 액센트 아이콘.
- **라이트/다크 모드 자동 적응**: 메뉴 UI가 시스템 외관 설정을 따라갑니다.
- **화면 깨우기 마진**: 잠금 임계값보다 +20 dBm 더 가까울 때만 화면이 켜져 옆방
  신호로 인한 오작동 방지.

### Changed
- 폰트를 Pretendard 단일 패밀리로 통일. 기존 serif/mono/body 혼용을 정리하고
  영문 라벨을 한글로 교체.
- 카운트다운 오버레이 사이즈를 화면 세로 절반의 정사각형으로 확대, 마지막 5초만
  표시하도록 동작 정리.

### Fixed
- 카운트다운이 1초 부모 타이머 드리프트로 끊겨 보이는 문제 — 오버레이 자체에
  50ms 자체 틱 도입.
- "0" 프레임이 잠시 깜빡이는 현상.
- 한글 IME 활성화 상태에서 암호 입력 시 알파벳이 누락되는 문제 — 암호 필드에
  ASCII-only 입력 컨텍스트 강제.
- 메뉴바 팝오버가 SecureField 포커스 변화로 닫혀 암호를 끝까지 입력할 수 없던
  현상 — 별도 NSWindow로 분리.

## [0.1.0] — 2026-05-27

### Added
- 초기 릴리스.
- BLE RSSI 기반 자리 비움 감지 + 단일 임계값 + 신호 끊김 허용 시간 상태 머신.
- 메뉴바 UI에서 디바이스 등록/교체, 거리 임계값(40~100 dBm) 및 신호 끊김 허용
  시간(15~60초) 슬라이더.
- `SACLockScreenImmediate`로 화면 잠금.
- `IOPMAssertionDeclareUserActivity`로 근접 시 화면 깨우기 (옵션).
- macOS 13+ `SMAppService`로 로그인 시 자동 시작.
- ad-hoc 코드사인 + DMG/ZIP 배포 스크립트.
