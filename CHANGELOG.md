# Changelog

이 프로젝트의 변경 사항을 기록합니다. 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를
따르고, 버전 번호는 [Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

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
