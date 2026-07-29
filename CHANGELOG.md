# Changelog

이 프로젝트의 변경 사항을 기록합니다. 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를
따르고, 버전 번호는 [Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

## [Unreleased]

## [0.6.0] — 2026-07-29

### Added
- **무신호 허용 시간과 잠금 카운트다운 시간을 각각 설정 가능.** 무신호 허용은
  5~60초(5초 단위, 기본 10초), 카운트다운은 1~30초(1초 단위, 기본 5초)입니다.
  기본 설정은 마지막 BLE 광고 후 `10초 대기 → 5초 카운트다운 → 잠금`으로
  동작합니다.
- **영구 SQLite 진단 로그와 메뉴 진단 카드 추가.** 앱 실행 세션, 설정,
  Bluetooth, 근접 판정, 화면 상태, 잠금·해제 요청과 실제 확인 결과를 구조화해
  `~/Library/Application Support/AutoLock/diagnostics.sqlite3`에 최대 90일,
  25,000건 보존합니다. 기존 JSONL 로그는 첫 실행 시 안전하게 이관합니다.
- 잠금·자동 해제 요청과 실제 화면 상태 변화를 correlation ID로 연결하고,
  5초 안에 확인되지 않으면 성공이 아닌 confirmation timeout으로 기록합니다.
- `AutoLock diagnose logging` 비파괴 진단 명령과 운영 분석 문서를 추가했습니다.

### Changed
- 거리 임계값 조정 단위를 10 dBm에서 **5 dBm**으로 세분화했습니다.
- 무신호 잠금 시점을 마지막 광고 시각에 고정해 평가 타이머의 다음 틱만큼
  카운트다운이 추가로 늦어지지 않도록 했습니다.
- 결정론적 제품 로직 라인 커버리지 **100% (1385/1385)**를 유지합니다.
  테스트는 212 → 235건으로 확대했습니다.

## [0.5.5] — 2026-07-11

### Security
- **자동 잠금 해제 암호의 Keychain ACL을 현재 AutoLock 서명으로 제한.** 제한된
  ACL을 만들지 못하면 암호를 저장하지 않으며, 이전 버전의 넓은 ACL로 저장된
  암호는 첫 실행 때 삭제해 사용자가 직접 다시 입력하도록 변경했습니다.
- **자가업데이트 진위 검증 추가.** SHA256에 더해 bundle ID, 마케팅 버전, 빌드
  번호, arm64 아키텍처, 실행 권한과 현재 앱의 designated requirement가 모두
  일치해야 교체를 허용합니다.
- 릴리스 인증서 leaf fingerprint를 저장소에 고정해 같은 이름의 다른 인증서로
  잘못 서명된 빌드가 배포되지 않도록 차단했습니다.

### Fixed
- 앱 교체 전에 기존 번들을 백업하고, 새 실행 파일이 health marker를 기록하지
  못하면 기존 앱으로 롤백하도록 자가업데이트를 원자화했습니다.
- 자가교체가 불가능한 상태에서 `DMG 받기` 버튼이 아무 동작도 하지 않던 문제를
  수정했습니다.
- 비밀번호 문자용 `CGEvent` 생성이 중간에 실패해도 입력 완료로 처리하고 Enter를
  보내던 문제를 수정했습니다.

### Changed
- macOS 시스템 연동을 `AutoLockSystemAdapters` 모듈로 분리하고, 업데이트 준비
  순서와 Keychain 마이그레이션 판단을 주입 가능한 정책/코디네이터로 추출했습니다.
- 결정론적 제품 로직 라인 커버리지 **100% (976/976)**를 릴리스 게이트로 강제합니다.
  테스트 192 → 212건. 네이티브 Keychain·CoreBluetooth·AppKit 경계의 제외 근거는
  `docs/TESTING.md`에 명시했습니다.

### Upgrade notes
- 자동 잠금 해제를 사용하던 경우 보안 ACL 마이그레이션으로 기존 저장 암호가
  삭제됩니다. 업데이트 후 로그인 암호를 한 번 다시 입력해야 합니다.

## [0.5.4] — 2026-07-11

### Fixed
- **AutoLock 토글이 꺼진 상태에서 디바이스 선택 창에 주변 기기가 전혀 표시되지
  않던 문제를 수정.** 페어링·교체용 BLE 스캔을 근접 모니터링 스캔과 독립적으로
  요청하도록 변경했습니다. 선택 창을 닫아도 근접 모니터링이 활성화돼 있으면 공유
  스캔을 중단하지 않도록 다중 스캔 수요를 추적합니다. 테스트 188 → 192건.

## [0.5.3] — 2026-06-23

### Fixed
- **자동 해제 중 저장된 비밀번호가 잠금 화면이 아닌 다른 곳에 입력되던 문제를
  수정(보안).** 자동 해제는 "화면이 잠겨 있다"고 판단한 뒤 최대 0.6초 기다렸다가
  비밀번호를 키 입력으로 주입한다. 그 사이 사용자가 Touch ID·Apple Watch·직접
  입력으로 먼저 잠금을 풀면, 뒤늦게 주입되는 평문 비밀번호가 잠금 화면이 아니라
  이미 풀린 데스크톱에서 포커스를 가진 앱(검색창·메모·채팅 등)에 그대로
  타이핑됐다. 이제 주입 직전·글자마다·Enter 직전에 잠금 상태를 다시 확인해,
  도중에 잠금이 풀리면 남은 입력과 Enter를 즉시 중단한다. 글자 단위 중단 로직은
  순수 함수 `UnlockKeystrokeSequencer` 로 분리해 단위 테스트로 고정. 테스트
  186 → 188건.

## [0.5.2] — 2026-06-22

### Fixed
- **자동 잠금 해제 발동선을 낮춤(−50 → −60 dBm).** 깨우기/자동해제 마진을
  20 → 10 dBm 으로 조정. 송신 출력이 약한 Apple Watch 는 손목을 키보드에
  올려도 −50 을 넘기 어려워 자동 해제가 영영 발화하지 않는 사례가 있었다.
  발동선을 끌어내려 워치도 현실적으로 도달하게 한다.

### Changed
- **로깅을 통합 로깅(os.Logger)으로 전환.** 기존 `NSLog` 는 GUI 릴리스 빌드에서
  `log show`·Console 에 신뢰성 있게 실리지 않아 "자동 해제가 왜 발화하지
  않았는가"를 사후 추적할 수 없었다. subsystem `com.local.autolock` 으로 전환해
  항상 조회 가능하게 한다:
  `log stream --predicate 'subsystem == "com.local.autolock"' --level info`
- **자동 해제 미발동 사유를 로깅.** 발화하지 않은 이유(약신호+실측 RSSI/발동선,
  이미 발화, 기기 미탐지, 토글 꺼짐)를 사유별로 남긴다. 매 틱 도배를 막기 위해
  사유 종류가 바뀔 때만 한 줄 기록.
- 정상 동작 로그는 `.info`(평소 디스크 미저장), 실패만 `.error`(디스크 보존)로
  분리해 저장용량 부담을 최소화. 테스트 181 → 183건.

## [0.5.1] — 2026-06-22

### Changed
- **신호 끊김 허용 기본값을 10초 → 15초로 조정.** 짧은 BLE 끊김에 더 관대해져
  순간적인 신호 누락으로 잠기는 경우를 줄입니다.
- **업데이트 파이프라인·BLE 상태 경계를 정리(내부 리팩토링, 동작 보존).** 릴리스
  형식 파싱(GitHub JSON·SHA256SUMS)과 자가교체 셸 스크립트 생성을 `AutoLockKit`
  어댑터로, 순수 선택·검증 규칙을 `AutoLockCore`로 분리. CoreBluetooth 의존을
  스캐너 한 곳으로 격리. 테스트 148 → 181건.

## [0.5.0] — 2026-06-21

### Added
- **완전 자동 업데이트(자가교체).** "업데이트" 버튼 한 번으로 ZIP 다운로드 →
  SHA256 검증 → 번들 교체 → 재실행까지 자동 완료. DMG 수동 드래그가 사라졌습니다.
  자가교체 불가 위치(App Translocation·쓰기 불가·ZIP 부재)는 기존 DMG 설치로 폴백.
- `diagnose self-update [--dry-run|--apply]` 서브커맨드.

### Changed
- **코드서명을 ad-hoc → 고정 self-signed 인증서로 전환.** ad-hoc은 빌드마다 코드
  해시가 변해 업데이트 후 블루투스·접근성 권한이 리셋됐습니다. 고정 인증서로
  designated requirement를 안정화해 **업데이트 후에도 권한이 유지**됩니다.

### Upgrade notes
- **v0.4.0 → v0.5.0**: 이번 한 번은 수동 드래그 설치 + 블루투스·접근성 권한 재허용이
  필요합니다. 이후 버전부터는 권한 유지된 채 자동 교체됩니다.

## [0.4.0] — 2026-06-20

### Added
- **GitHub Releases 기반 자동 업데이트.** 최신 릴리스를 확인해 새 버전이 있으면
  메뉴에 업데이트 버튼을 노출하고, `arm64` DMG를 내려받아 **`SHA256SUMS.txt`로
  검증(fail-closed)** 후 엽니다. 마지막 드래그 설치만 수동. 결정 로직은 전부
  `AutoLockCore` 순수 타입으로 분리.
- `diagnose update` 서브커맨드.

### Changed
- **신호 끊김 허용 시간을 10초로 고정**하고 조정 슬라이더를 제거했습니다(이전 15~60초).

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
