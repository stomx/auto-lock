---
template: analysis
feature: proximity-timing-fix
project: AutoLock
date: 2026-06-01
author: 주재만
phase: check
type: e2e-manual
---

# proximity-timing-fix E2E Manual Test Checklist

> 자동화 불가능한 실기기 시나리오를 수동으로 검증하는 체크리스트

## 배경

순수 로직(**ProximityEvaluator**, **BestDeviceSelector**, **WakeDecision**)과 컨트롤러 배선(**ProximityController** + Fake/Spy 주입)은 swift-testing 33건으로 자동 검증됨.

그러나 다음은 자동화 불가능:
- **실제 CoreBluetooth 콜백** — 시뮬레이터는 BLE 기기 발견 불가
- **실 BLE 기기 근접/이탈** — 물리적 거리 변화 필요
- **실제 macOS 화면 잠금/깨우기** — 시스템 권한 필요
- **메뉴 트래킹 중 타이머 동작** — UIKit 이벤트 루프 상호작용

이 문서가 그 갭을 메운다. **v0.3.0 타이밍 결함 수정 검증** 핵심:
- FR-01: 프루닝 임계값 > 부재 판정점 (grace × 2)
- FR-03: 평가 타이머 `.common` 모드 (메뉴 트래킹 중 동작)
- FR-04: 토글 OFF 시 BLE 스캔 정지

---

## 사전 준비

### 환경 필요사항

| 항목 | 요구사항 |
|------|----------|
| **Mac** | macOS 13.0+ (Bluetooth 권한 필요) |
| **BLE 기기** | 1개 (안드로이드 폰, nRF Connect 켜기 또는 BLE 광고 장치) |
| **Xcode** | 15.3+ 또는 Swift CLI 6.0+ |
| **권한** | 설정 > Bluetooth 허용, 손쉬운 사용(Accessibility) 권한 |
| **Keychain** | 자동 잠금 해제 테스트 시 macOS 계정 비밀번호 저장 필요 |

### 빌드 및 실행

```bash
# 빌드
cd /Users/searchdoc/Work/stomx/auto-lock
swift build

# 또는 release 빌드
swift build -c release

# 실행
.build/debug/AutoLock
# 또는
.build/release/AutoLock
```

실행 후 메뉴바(우측 상단)에 🔓/🔄/🔒 아이콘이 나타나는지 확인.

### 초기 설정

1. **AutoLock 메뉴 열기**: 메뉴바 아이콘 클릭
2. **BLE 기기 추적 설정**:
   - "추적 기기" 섹션에서 사용할 BLE 기기(안드로이드 폰 등) 등록
   - 기기 신호가 강한 거리에서 추가 (메뉴 상단에 기기 RSSI 표시됨)
3. **Grace Period 확인**: 슬라이더 기본값 15초 메모 (변경 시 해당 값 사용)
4. **자동 잠금 토글**: "활성화" 체크박스 ON (활성화)

---

## 시나리오 체크리스트

### 1. 정상 근접 — 잠금 안 됨

**사전조건:**
- AutoLock 활성화됨 (toggle ON)
- BLE 기기 1개 추적 등록됨
- 자동 잠금 토글 OFF일 때 메뉴에 "활성화" 표시 X

**절차:**
1. BLE 기기를 Mac 옆 약 2~3m 거리에 놓음 (강한 신호)
2. 메뉴 아이콘 확인
3. 화면 상태 확인
4. 10초 이상 유지

**기대결과:**
- 메뉴 아이콘: **🔓 (lock.open.fill)**
- 메뉴 상태: "감시 중" 또는 "근처"
- 화면: **잠기지 않음** (켜진 상태 유지)
- RSSI 표시: 음수 dBm으로 표시 (예: -50 dBm)

**합격 기준:**
- [ ] 메뉴 아이콘이 🔓
- [ ] 화면이 잠기지 않음
- [ ] RSSI 강신호 표시 (threshold 이상)

---

### 2. 자리 비움 → 카운트다운 → 잠금 (Grace 경로)

**사전조건:**
- AutoLock 활성화됨
- Grace Period = 15초 (또는 확인된 값)
- 자동 잠금 토글 ON
- 화면이 켜져 있음

**절차:**
1. BLE 기기를 강신호 거리에서 시작 (🔓 아이콘)
2. 기기를 약 5m 이상 멀리 (신호 약화, 임계값 근처)
3. 메뉴 아이콘 변화 관찰
4. 화면 중앙의 **카운트다운 오버레이** 나타나는지 확인
5. 오버레이가 0 도달할 때까지 대기 (약 15초)

**기대결과:**
- T=0s: 아이콘 변경 (🔄 lock.rotation)
- T=1~10s: 상태 "카운트다운" (그러나 오버레이 없음 — grace 마지막 5초 전)
- T=10~15s: **화면 중앙에 숫자 오버레이** ("5", "4", "3", "2", "1" 표시)
- T=15s: 화면 **잠김** (로그인 화면 표시)
- 메뉴 아이콘: **🔒 (lock.fill)**

**합격 기준:**
- [ ] 신호 약화 후 아이콘이 🔄로 변경
- [ ] Grace 마지막 5초에 카운트다운 오버레이 표시
- [ ] 오버레이가 0에 도달 후 화면 잠김
- [ ] 로그인 화면 나타남

**핵심 회귀 검증:**
이 시나리오는 **v0.3.0 이전 버그 재현**. 이전엔 프루닝이 너무 빨라 이 경로가 도달하지 않았음.

---

### 3. 신호 급락 즉시 잠금 (Definitive Away)

**사전조건:**
- AutoLock 활성화됨
- Grace Period = 15초
- BLE 기기 근처에서 시작 (🔓)
- 자동 잠금 토글 ON

**절차:**
1. BLE 기기 전원 **즉시 OFF** 또는 극도로 멀리 치움 (신호 < definitiveAwayThreshold)
2. 메뉴 아이콘 및 화면 상태 즉시 확인
3. 카운트다운 오버레이 없음을 확인

**기대결과:**
- 카운트다운 오버레이 표시 **없음**
- 즉시 화면 잠김 (1~2초 내)
- 메뉴 아이콘: **🔒**
- Console.app 로그: "lock invoked (ok) reason=signalCrashed" 또는 "reason=signal stale..."

**합격 기준:**
- [ ] 카운트다운 없이 즉시 잠김
- [ ] 아이콘이 🔒로 변경
- [ ] 화면 잠금까지 시간 < 2초

---

### 4. 장기 부재 즉시 잠금 (Absence 경로 — 핵심 회귀)

**사전조건:**
- AutoLock 활성화됨
- Grace Period = 15초
- BLE 기기가 완전히 보이지 않음 (스캔 범위 밖 또는 전원 OFF)
- 자동 잠금 토글 ON

**절차:**
1. 메뉴에서 BLE 기기 신호가 "보이지 않음"이 될 때까지 대기 (약 15초)
2. 기기가 스캔 맵에서 사라질 때까지 추가 대기 (약 grace × 2 초 = 30초)
3. 이 동안 메뉴 상태 모니터링

**기대결과:**
- T ≈ 15초: 카운트다운 시작 (오버레이 나타남)
- T ≈ 30초: 프루닝 임계값 도달 → 즉시 잠금 (카운트다운 계속하지 않음)
- 화면 잠김
- Console 로그: "lock invoked (ok) reason=signalStaleSeconds(30)" 또는 유사

**합격 기준:**
- [ ] 장기 부재 후 즉시 잠김 (다시 카운트다운 안 함)
- [ ] 프루닝 임계값(grace × 2 + margin) 이후에 기기 완전 제거
- [ ] 이 분기가 도달 가능함을 입증 (LockTuning 불변식: **프루닝 > 부재 판정점**)

**핵심 불변식 검증:**
```
pruneAfterSeconds = absencePointSeconds + pruneMarginSeconds
                  = (grace * 2) + 2
                  = 30 + 2 = 32초
```
따라서 evaluator가 `age > 30` 분기(즉시 잠금)에 도달한 후에만 프루닝이 발생.

---

### 5. 메뉴 열린 채로 잠금 (.common 타이머 검증)

**사전조건:**
- AutoLock 활성화됨
- Grace Period = 15초
- BLE 기기가 근처에서 시작 (🔓)
- 자동 잠금 토글 ON

**절차:**
1. BLE 기기를 Grace 범위로 이동 (신호 약화 시작)
2. 카운트다운 오버레이가 표시될 때까지 대기 (약 10초)
3. **메뉴바 아이콘을 클릭하여 메뉴 팝오버 열기** (그대로 유지)
4. 메뉴 내에서 팝오버가 닫히지 않으면서 오버레이 카운트다운 계속 진행 확인
5. 0에 도달할 때까지 메뉴 유지

**기대결과:**
- 메뉴 팝오버가 **열린 상태 유지**
- 화면 중앙의 카운트다운 오버레이가 **계속 진행** ("5", "4", "3", ... "1")
- 0 도달 후 화면 잠김 (메뉴 자동 종료)
- 예전 .default 모드에서는 메뉴 트래킹 중 타이머가 정지했음

**합격 기준:**
- [ ] 메뉴 열린 채로 타이머가 멈추지 않음
- [ ] 카운트다운이 계속 진행됨
- [ ] 0 도달 후 화면 잠김

**기술 배경:**
v0.3.0에서 평가 타이머를 `.common` 모드로 등록하여 메뉴 트래킹(UI 이벤트) 중에도 실행되도록 수정.

---

### 6. 토글 OFF 시 스캔 정지

**사전조건:**
- AutoLock 활성화됨 (toggle ON)
- BLE 기기 추적 중

**절차:**
1. 메뉴에서 활성화 토글 **OFF**로 변경
2. 메뉴 상태 텍스트 확인
3. 일정 시간 대기 (약 5초)
4. 활성화 토글 다시 **ON**으로 변경
5. 메뉴 상태 다시 확인

**기대결과:**
- 토글 OFF 직후:
  - 메뉴 상태: "준비됨" 또는 "스캔 중지됨" (비활성 상태)
  - 메뉴 아이콘: 🔓 (변경 없음) 또는 🔐 (스캔 비활성)
  - BLE 스캔 중지 (내부적)
- 토글 OFF 중 기기 접근 시: 화면이 **잠기지 않음**
- 토글 ON 복귀 직후:
  - 메뉴 상태: "감시 중" (스캔 재개)
  - 신호 다시 추적됨 (메뉴에 RSSI 표시)

**합격 기준:**
- [ ] 토글 OFF: 메뉴 상태 변경 (비활성)
- [ ] 토글 OFF 중 기기 접근해도 잠기지 않음
- [ ] 토글 ON: 상태 "감시 중" 복귀, RSSI 다시 나타남
- [ ] 스캔이 실제로 정지/재개됨 (Console 로그 확인 가능)

**코드 검증:**
`ProximityController.swift:58~64` —— `settings.$enabled` 구독에서 토글 변경 시 `scanner.startScanning()` / `stopScanning()` 호출.

---

### 7. 근접 복귀 시 화면 깨우기

**사전조건:**
- AutoLock 활성화됨
- wakeOnProximity 토글 ON
- autoUnlock 토글 **OFF** (먼저 깨우기만 테스트)
- 근처 BLE 기기 추적 중

**절차:**
1. 화면을 수동으로 잠금 (Ctrl+Command+Q 또는 System Settings)
2. BLE 기기를 로그인 화면 활성화 거리에 서서히 접근
3. RSSI가 threshold + wakeMargin 이상이 될 때까지 가져옴
4. 화면 상태 모니터링

**기대결과:**
- 기기가 wakeMargin 거리에 도달:
  - 디스플레이 깨어남 (화면 켜짐)
  - Touch ID 또는 비밀번호 입력 프롬프트 표시
- **1회만 발화** (기기가 근처에 있어도 반복 깨우기 안 함)
- 사용자가 비밀번호 입력 또는 Touch ID 사용 가능

**합격 기준:**
- [ ] 기기 접근 시 화면 깨어남
- [ ] 인증 프롬프트 표시
- [ ] 1회만 발화 (반복 안 함 — `wakeFiredForCurrentLock` 플래그 검증)

**참고:**
hardened runtime 설정에 따라 OS가 무시할 수 있음. 권한 설정 재확인.

---

### 8. 자동 잠금 해제 (autoUnlock ON, 선택사항)

**사전조건:**
- AutoLock 활성화됨
- wakeOnProximity 토글 ON
- **autoUnlock 토글 ON**
- Keychain에 macOS 계정 비밀번호 저장됨 (설정 > Keychain)
- Accessibility 권한 허용됨 (System Settings > Privacy & Security)

**절차:**
1. 화면을 잠금
2. BLE 기기를 wakeMargin 거리에 가져옴
3. 화면 깨어나고 비밀번호 입력 프롬프트 표시 대기
4. 키스트로크 시뮬레이션 감시 (입력 필드에 자동 입력 시도)

**기대결과:**
- 기기 접근 후 약 600ms (keystrokeDelay):
  - 비밀번호 자동 입력 시도
  - 입력 필드에 문자 나타남 (또는 입력 완료, OS 정책에 따라)
  - 로그인 성공 (정상 경우)
- Console 로그: "auto-unlock attempt result=success" 또는 유사

**합격 기준:**
- [ ] 기기 접근 시 화면 깨어남
- [ ] 약 600ms 후 비밀번호 자동 입력 시도
- [ ] 로그인 성공 (또는 OS/권한에 의해 무시, 에러 로그 표시)

**제약사항:**
- macOS 보안 정책에 따라 자동 입력 차단 가능
- Accessibility 권한 재확인 필요
- 베스트 에포트 테스트 (모든 환경에서 작동 보장 불가)

---

## 실패 기록 양식

실패 시 다음을 기록하고 보고:

```markdown
### 실패 기록

**시나리오:** [번호 및 이름]
**환경:** macOS [버전], Xcode [버전], Grace Period [초]
**관측:**
- [현상 설명]
- [기대 vs. 실제]
- [스크린샷 또는 비디오 링크]

**Console 로그:**
```
[Console.app에서 "AutoLock" 필터로 추출한 로그]
```

**원인 추정:**
- [기술적 분석]

**재현 단계:**
1. [단계 1]
2. [단계 2]
```

---

## 합격 판정

| 단계 | 필수/선택 | 합격 기준 |
|------|----------|---------|
| 1. 정상 근접 | **필수** | 🔓 아이콘, 잠기지 않음 |
| 2. Grace 카운트다운 | **필수** | 오버레이 표시, 정시 잠금 |
| 3. 신호 급락 | **필수** | 즉시 잠금, 카운트다운 없음 |
| 4. 장기 부재 | **필수** | 프루닝 후 즉시 잠금 (FR-01 검증) |
| 5. 메뉴 열린 상태 | **필수** | 타이머 계속 진행 (FR-03 검증) |
| 6. 토글 OFF | **필수** | 스캔 정지, 잠금 안 됨 (FR-04 검증) |
| 7. 화면 깨우기 | 선택* | 기기 접근 시 깨어남 |
| 8. 자동 잠금 해제 | 선택* | 자동 입력 시도 |

**선택***: 환경/권한 의존 (베스트 에포트)

**최종 결과:**
- **PASS**: 필수 1~6 모두 통과
- **PASS w/ Notes**: 필수 통과, 선택 일부 실패 (권한/환경 이유)
- **FAIL**: 필수 중 1개 이상 실패

---

## Console 로그 필터

실시간 로그 모니터링:

```bash
log stream --predicate 'process == "AutoLock"' --level debug
```

또는 Console.app:
1. Console.app 열기
2. 우측 상단 검색: "AutoLock"
3. 필터 적용

주요 로그 키워드:
- `"lock invoked"` — 화면 잠금 수행
- `"proximity wake"` — 화면 깨우기 시도
- `"auto-unlock attempt"` — 자동 해제 시도
- `"reason=signalStaleSeconds"` — Grace 카운트다운
- `"reason=signalCrashed"` — 신호 급락 즉시 잠금

---

## 참고자료

- **설계**: [proximity-timing-fix.design.md](../02-design/features/proximity-timing-fix.design.md)
- **계획**: [proximity-timing-fix.plan.md](../01-plan/features/proximity-timing-fix.plan.md)
- **분석**: [proximity-timing-fix.analysis.md](../03-analysis/proximity-timing-fix.analysis.md)
- **코드**: `Sources/AutoLockCore/ProximityEvaluator.swift`, `Sources/AutoLockKit/ProximityController.swift`
- **테스트**: `Tests/AutoLockCoreTests/ProximityEvaluatorTests.swift` (33개 자동 테스트)

