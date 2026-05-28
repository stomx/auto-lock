# AutoLock 현황

작성일: 2026-05-28

## 한 줄 요약

BLE 신호 강도 기반 macOS 자동 잠금 메뉴바 앱 (실험적 자동 해제 포함). v0.2.0
ad-hoc 서명으로 GitHub Release 배포 중. 코드 리뷰 후 1차 슬롭 정리 완료, 테스트
인프라와 CRITICAL 보안 항목은 미착수.

## 배포 상태

- **저장소**: https://github.com/stomx/auto-lock (public)
- **최신 릴리스**: [v0.2.0](https://github.com/stomx/auto-lock/releases/tag/v0.2.0)
  - `AutoLock-0.2.0-arm64.dmg` (1.3 MB)
  - `AutoLock-0.2.0-arm64.zip` (933 KB)
  - `SHA256SUMS.txt`
- **요구사항**: macOS 13+, Apple Silicon
- **서명**: ad-hoc (Apple Developer 인증 없음 → 첫 실행 시 Gatekeeper 우회 필요)

## 기능 현황

| 기능 | 상태 | 비고 |
|------|------|------|
| BLE RSSI 기반 자리 비움 감지 | 안정 | EWMA 0.3 평활화 |
| 단일 임계값 + 신호 끊김 허용 시간 | 안정 | 40~100 dBm / 15~60초 |
| `SACLockScreenImmediate`로 잠금 | 안정 | macOS 26 호환 검증 |
| 카운트다운 오버레이 (마지막 5초) | 안정 | 50ms 자체 틱, 화면 절반 크기 |
| `IOPMAssertionDeclareUserActivity` 화면 깨우기 | 안정 | wakeMargin +20 dBm 적용 |
| 자동 잠금 해제 (Keychain + CGEvent) | **실험적** | 잠금 화면 키 차단 환경에선 무동작 |
| 로그인 시 자동 시작 | 안정 | SMAppService |
| 라이트/다크 모드 자동 적응 | 안정 | NSColor dynamic provider |
| 한국어 IME 자동 ABC 전환 | 안정 | TIS + `allowedInputSourceLocales` 4단 조합 |
| Apple Watch Auto Unlock | **macOS 기본 기능** | 본 앱이 구현한 것 아님 |

## 코드 구조

```
Sources/AutoLock/
  AutoLockApp.swift          # SwiftUI MenuBarExtra entry point
  BLEScanner.swift           # CoreBluetooth scanner + RSSI smoothing
  ProximityController.swift  # 상태 머신 (LockReason / ControllerStatus enum)
  Settings.swift             # UserDefaults 영구화
  ScreenLocker.swift         # SACLockScreenImmediate 래퍼
  WakeController.swift       # IOPMAssertionDeclareUserActivity 래퍼
  UnlockTrigger.swift        # CGEvent 키스트로크 합성
  KeychainStore.swift        # legacy Keychain (silent ACL)
  CountdownOverlay.swift     # NSPanel 카운트다운
  LockTuning.swift           # 도메인 튜닝 상수 단일 소스
  MenuView.swift             # 모든 SwiftUI UI + ASCII-only SecureField
  PickerWindow.swift         # 디바이스 선택 NSWindow
  PasswordWindow.swift       # 암호 설정 NSWindow + IME 회피
  LaunchAtLogin.swift        # SMAppService 래퍼
  PermissionPrompt.swift     # 첫 실행 안내 다이얼로그
Resources/
  Info.plist
  icon.svg                   # 아이콘 원본 (자물쇠 + 표류 신호 점)
  AppIcon.icns               # 빌드시 번들에 포함
scripts/
  render_icon.swift          # SVG → iconset → icns 변환
build_app.sh                 # SPM → AutoLock.app 패키징
release.sh                   # DMG + ZIP 배포 빌드
```

## 코드 리뷰 결과 (2026-05-28)

전수 리뷰: code-reviewer agent (opus). 판정: REQUEST CHANGES.

### CRITICAL (5건) — **미해결**

| ID | 항목 | 위치 |
|----|------|------|
| C3 | KeychainStore의 `SecAccess*` 반환값 미검사 + zeroize 없는 평문 password 보관 | `KeychainStore.swift` |
| T1/T2/T4 | `ProximityController.shared` 싱글톤 + DI 부재 → 테스트 불가 | `ProximityController.swift` |
| D1 | ProximityController가 모든 시스템 정적 함수 직접 호출 (DIP 위반) | `ProximityController.swift` |
| — | `Tests/` 디렉토리 자체가 없음, `Package.swift`에 `testTarget` 미선언 | — |

### MAJOR (15건) — **일부 해결**

해결됨:
- **C1** 매직넘버 분산 → `LockTuning.swift`로 통합 (8개 상수)
- **C28** `definitiveAwayMargin`을 `static let` / `LockTuning`으로
- **C33** 미사용 `lockThreshold`/`unlockThreshold` 별칭 제거
- **C14** 컨트롤러 한국어 침투 → `LockReason`/`ControllerStatus` enum + 뷰 localize
- **C20** 파일명 vs 타입명 불일치 (`LockController.swift` → `ScreenLocker.swift`)

미해결 주요 항목:
- **S1** ProximityController SRP 위반 (7가지 책임)
- **S2** MenuView 911라인 (디자인 토큰 + 컴포넌트 + 뷰 모두 한 파일)
- **C7** `awaySince` nil 리셋이 4곳에 분산 → enum 상태 모델링 필요
- **C9/C10** Timer mode가 default → 메뉴 트래킹 중 정지
- **C11** `BLEScanner.smoothing` 사전 정리 안 됨 (메모리 누수)
- **C13** `Settings.enabled=false`일 때 BLE 스캔 미정지 (배터리)
- **C15** CountdownOverlay 매초 재시작 (멱등성 가드 부재)
- **C18** lockThreshold/unlockThreshold 별칭 제거 후 hysteresis 의도 결정 필요

### MINOR (14건+) — **일부 해결**

해결됨:
- PasswordWindow의 no-op `performKeyEquivalent` 제거, 부정확한 주석 정정

미해결: NSLog → `os.Logger` 전환, i18n bundle, dead code 추가 정리, 등.

## 슬롭 정리 1차 패스 결과 (2026-05-28)

5개 패스 모두 행동 보존, 빌드 통과:

1. **Dead code** — 미사용 별칭 2개 제거
2. **Magic numbers** — 8개 상수를 `LockTuning`으로 통합
3. **Boundary** — 컨트롤러 → enum publish, 뷰가 한국어 매핑
4. **Duplication** — PasswordWindow 노이즈 제거 (`SingletonHostedWindow` 추출은 YAGNI 판단으로 보류)
5. **Naming** — 파일명/타입명 일치

## 다음 라운드 후보 (우선순위)

### Phase 1: 즉시 (보안/안전성)

- [ ] **C3 보안**: `SecAccessCreate` / `SecACLSetContents` 반환값 검사, 실패 시 false
- [ ] **C13 배터리**: `Settings.enabled=false` 시 `scanner.stopScanning()` 호출
- [ ] **C9/C10 일관성**: 모든 `Timer.scheduledTimer`를 `RunLoop.main.add(.common)`으로 통일
- [ ] **C7 누수 방지**: `awaySince`를 `enum LockTimerState { case idle, counting(Date) }`로 모델링

### Phase 2: 1주 내 (테스트 가능성)

- [ ] `Tests/AutoLockTests/` 디렉터리 + `Package.swift`에 testTarget 추가
- [ ] `ScreenLocking` / `DisplayWaking` / `Clock` / `BLESignaling` protocol 도입
- [ ] `ProximityController.init`에 의존성 주입 가능하게 변경 (싱글톤 유지하되 init 공개)
- [ ] 6개 우선 테스트 작성 (evaluate 결정 트리, handleAway 경계, maybeWakeDisplay 게이팅, Settings 클램핑, BLEScanner 필터/EWMA, clearStale)

### Phase 3: 2주 내 (구조)

- [ ] `MenuView.swift` 분할 (Theme/, Components/, Views/)
- [ ] `ProximityController` 책임 분할 (Evaluator / Orchestrator / Presenter)

### Phase 4: 보강

- [ ] `os.Logger`로 NSLog 대체
- [ ] i18n bundle 분리
- [ ] BLEScanner 메모리 누수 (`smoothing` 사전 정리)

## 알려진 한계

- BLE RSSI 정밀도 낮음 (사람 몸이 신호 사이에 들어가면 -10 dBm 이상 떨어짐)
- iOS BLE 식별자 주기적 회전 → 신호 송출 앱 권장 (nRF Connect 등)
- 자동 해제는 macOS 잠금 화면 키 차단 정책에 좌우 → Apple Watch 병행 권장
- ad-hoc 서명이라 빌드 시마다 cdhash 변경 → Keychain ACL 첫 접근 다이얼로그 한 번 발생 가능
