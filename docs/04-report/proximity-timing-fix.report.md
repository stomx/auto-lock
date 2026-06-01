---
template: report
version: 1.1
feature: proximity-timing-fix
project: AutoLock
date: 2026-06-01
author: 주재만
---

# proximity-timing-fix Completion Report

> **Status**: Complete (커밋 대기 중 — 변경사항 미커밋)
>
> **Project**: AutoLock (BLE RSSI 기반 macOS 메뉴바 자동 잠금)
> **Version**: v0.2.1 → v0.3.0 (Phase 1)
> **Author**: 주재만
> **Completion Date**: 2026-06-01
> **PDCA Cycle**: #1 (v0.3.0)

---

## Executive Summary

### 1.1 Project Overview

| Item | Content |
|------|---------|
| Feature | proximity-timing-fix (근접 판정 시간 결함 3건 수정 + 도메인 로직 분리·테스트) |
| Start Date | 2026-05-29 |
| End Date | 2026-06-01 |
| Duration | 약 3일 (Plan/Design 05-29, 구현·Check 05-31~06-01) |

### 1.2 Results Summary

```
┌─────────────────────────────────────────────┐
│  Completion Rate: 100%                       │
├─────────────────────────────────────────────┤
│  ✅ Complete:     5 / 5 Success Criteria     │
│  ✅ Tests:       33 / 33 passed              │
│  ✅ Match Rate:  100%                        │
│  ✅ Build:       debug + release 통과         │
│  ⏳ 커밋:        대기 중 (미커밋)             │
└─────────────────────────────────────────────┘
```

> **테스트 33건 내역**: 순수 로직 25건(ProximityEvaluator 10 + LockTuning 3 + BestDeviceSelector 5 + WakeDecision 7) + 컨트롤러 배선 통합 8건(Fake/Spy 의존성 주입). 초기 12건 → DI 리팩터링으로 +21건.
>
> **수동 검증 갭**: 실 BLE 하드웨어 근접/이탈, 실제 화면 잠금·깨우기, 메뉴 트래킹 중 `.common` 타이머 동작은 자동화 불가 → [수동 E2E 체크리스트](../03-analysis/proximity-timing-fix.e2e-manual.md) 8개 시나리오로 대체(실기기에서 사람이 수행).

### 1.3 Value Delivered

| Perspective | Content |
|-------------|---------|
| **Problem** | `BLEScanner`의 고정 8초 프루닝이 grace 하한(15초)보다 짧아, `evaluate()`의 stale/absence 즉시잠금 분기가 절대 도달 불가능한 죽은 코드였다. 또한 평가 타이머가 `.default` RunLoop 모드라 메뉴 트래킹 중 정지 가능했고, 토글 OFF 후에도 BLE 스캔이 계속 돌았다. |
| **Solution** | "사라짐" 판정 시간 상수를 `LockTuning` 단일 출처로 일원화 — 프루닝 임계값을 `absencePointSeconds + pruneMarginSeconds`로 연동. 시간 판정을 순수 함수 `ProximityEvaluator.decide()`로 추출해 `AutoLockCore` 라이브러리로 완전 분리(Clean Architecture, Option B). 평가 타이머 `.common` 모드 등록, 토글 OFF 시 `stopScanning()` 연결. |
| **Function/UX Effect** | 핵심 불변식 `pruneAfterSeconds > absencePointSeconds`가 grace 15~60 전 구간에서 보장되어 stale/absence 잠금 분기가 실제 도달 가능해짐(`pruneAlwaysOutlivesAbsencePoint` 전수 검증). 순수 로직뿐 아니라 컨트롤러 배선까지 의존성 주입으로 검증 — swift-testing 33건 전부 통과, Design Match Rate 100%. |
| **Core Value** | 자동 잠금의 핵심 안전 보장(자리를 비우면 반드시 잠긴다)이 결함 없이 작동하며, CoreBluetooth/AppKit 무의존 순수 도메인 + 프로토콜 주입형 컨트롤러로 향후 회귀를 단위·통합 테스트로 차단한다. |

---

## 1.4 Success Criteria Final Status

> Plan §4 / Requirements 기준. 현재 Analysis(2026-06-01) 기준 최종 평가.

| # | Criteria | Status | Evidence |
|---|---------|:------:|----------|
| FR-01 | 프루닝 임계값이 absence 판정 시점보다 길어 stale·absence 판정까지 디바이스 잔존 | ✅ Met | `LockTuning.swift:77-79` `pruneAfterSeconds = absencePointSeconds + pruneMarginSeconds`; `LockTuningTests` `pruneAlwaysOutlivesAbsencePoint`(grace 15~60 전수) |
| FR-02 | `decide()`의 stale 카운트다운/즉시잠금 분기가 실제 도달 가능 | ✅ Met | `ProximityEvaluator.decide` 전 분기 순수 이식; 테스트 #3·#4(stale), #5(crash), #6(near), #7(weak), #8(unseen), #9(grace 만료), #10(overlay) |
| FR-03 | 평가 타이머 `.common` RunLoop 모드 등록 | ✅ Met | `ProximityController.swift:37` `RunLoop.main.add(timer, forMode: .common)` |
| FR-04 | 토글 OFF 시 `stopScanning()` 호출 → `isScanning == false` | ✅ Met | `ProximityController.swift:44` `else { self.scanner.stopScanning() }` |
| FR-05 | 시간 판정 로직을 CoreBluetooth 없이 단위 테스트로 검증 | ✅ Met | `Tests/AutoLockCoreTests/` 25건 + `Tests/AutoLockKitTests/` 컨트롤러 배선 통합 8건 = swift-testing 33 케이스 전부 통과 |

**Success Rate**: 5/5 criteria met (100%)

> **검증 심화 (후속 작업, 2026-06-01)**: "정상 동작 확인" 요청에 따라 검증 범위를 순수 로직 → 컨트롤러 배선까지 확장. `ProximityController`를 신규 `AutoLockKit` 라이브러리 타깃으로 분리하고 부수효과 5종(`ScreenLocking`/`DisplayWaking`/`UnlockTriggering`/`OverlayPresenting`/`ProximityScanning`)을 프로토콜로 추출해 생성자 주입화. Fake/Spy 의존성으로 enabled 게이팅·best-device 선택·stale/absence/crash 잠금·오버레이 표시·wake/unlock 분기·스캐너 토글 시퀀싱을 통합 테스트로 검증. 실 하드웨어 의존 시나리오는 [수동 E2E 체크리스트](../03-analysis/proximity-timing-fix.e2e-manual.md)로 분리.

## 1.5 Decision Record Summary

> Plan→Design 의사결정 체인과 결과. (PRD 단계는 본 사이클에서 미수행 — 코드 리뷰 발(發) 핫픽스성 사이클)

| Source | Decision | Followed? | Outcome |
|--------|----------|:---------:|---------|
| [Plan] | 코드 리뷰 발견 결함 3건(프루닝-grace 충돌 / 타이머 RunLoop 모드 / 토글 OFF 스캔 미정지)을 단일 사이클로 통합 처리 | ✅ | 세 결함 모두 동일 근본원인(시간 상수 분산)으로 묶여 단일 출처화로 동시 해소 |
| [Design] | Architecture Option B(완전 분리 Clean) 선택 — `AutoLockCore` 라이브러리 신설, 도메인 타입 전면 이전 | ✅ | `AutoLockCore` 타깃 생성, 도메인 enum/struct를 `public`으로 이전, `Sources/AutoLock/LockTuning.swift` 삭제 |
| [Design] | 시간 판정을 순수 함수 `ProximityEvaluator.decide()`로 추출 (부수효과는 컨트롤러 잔류) | ✅ | `ProximityEvaluator`(Foundation only) 신설, 컨트롤러는 `Action`별 부수효과 적용으로 위임 |
| [Design] | XCTest 부재 환경(Xcode 없음) → swift-testing 채택 + `scripts/test.sh`로 rpath 우회 실행 | ✅ | swift-testing 12건 작성·통과, `./scripts/test.sh`로 CLI 실행 경로 확보 |

---

## 2. Related Documents

| Phase | Document | Status |
|-------|----------|--------|
| Plan | [proximity-timing-fix.plan.md](../01-plan/features/proximity-timing-fix.plan.md) | ✅ Finalized |
| Design | [proximity-timing-fix.design.md](../02-design/features/proximity-timing-fix.design.md) | ✅ Finalized |
| Check | [proximity-timing-fix.analysis.md](../03-analysis/proximity-timing-fix.analysis.md) | ✅ Complete (Match Rate 100%) |
| 수동 E2E | [proximity-timing-fix.e2e-manual.md](../03-analysis/proximity-timing-fix.e2e-manual.md) | ✅ 체크리스트 8건 (실기기 수행 대기) |
| 코드 리뷰 | [code-review-2026-05-29.md](../03-analysis/code-review-2026-05-29.md) | ✅ 사이클 트리거 |
| Act | 본 문서 | 🔄 작성 완료 |

---

## 3. Completed Items

### 3.1 Functional Requirements

| ID | Requirement | Status | Notes |
|----|-------------|--------|-------|
| FR-01 | 프루닝-grace 연동 (Critical) | ✅ Complete | `LockTuning.pruneAfterSeconds` 단일 출처 |
| FR-02 | stale/absence 분기 도달성 | ✅ Complete | `ProximityEvaluator.decide` 순수 이식 |
| FR-03 | 평가 타이머 `.common` 모드 | ✅ Complete | `CountdownOverlay`와 동일 패턴 |
| FR-04 | 토글 OFF 시 `stopScanning()` | ✅ Complete | `$enabled` sink else 분기 추가 |
| FR-05 | 순수 로직 단위 테스트 | ✅ Complete | swift-testing 12건 |

### 3.2 Non-Functional Requirements

| Item | Target | Achieved | Status |
|------|--------|----------|--------|
| 정확성 | stale/absence 분기 도달 가능성 증명 | grace 15~60 전수 + 12/12 테스트 | ✅ |
| 성능 | 평가 주기(1Hz)·메모리 회귀 없음 | 1Hz 유지, prune 마진 +2s만 추가 | ✅ |
| 호환성 | grace 카운트다운·오버레이 동작 보존 | 분기·오버레이 윈도우 보존 확인 | ✅ |
| 빌드 | `swift build` 통과 | `Build complete!` | ✅ |

### 3.3 Deliverables

| Deliverable | Location | Status |
|-------------|----------|--------|
| 순수 도메인 라이브러리 | `Sources/AutoLockCore/` (LockTuning, ProximityTypes, Devices, ProximityEvaluator, BestDeviceSelector, WakeDecision, UnlockOutcome) | ✅ |
| 주입형 컨트롤러 라이브러리 | `Sources/AutoLockKit/` (ProximityController, BLEScanner, Settings, ProximityServices 프로토콜 5종) | ✅ |
| 조립 루트 + 어댑터 | `Sources/AutoLock/` (AutoLockApp, ProximityServiceAdapters, UI) | ✅ |
| 단위 테스트 | `Tests/AutoLockCoreTests/` (ProximityEvaluator/LockTuning/BestDeviceSelector/WakeDecision) — 25건 | ✅ |
| 통합 테스트 | `Tests/AutoLockKitTests/ProximityControllerTests.swift` (Fake/Spy 주입) — 8건 | ✅ |
| 수동 E2E 체크리스트 | `docs/03-analysis/proximity-timing-fix.e2e-manual.md` — 8 시나리오 | ✅ |
| 테스트 실행 스크립트 | `scripts/test.sh` (swift-testing rpath 우회) | ✅ |
| 빌드 구성 | `Package.swift` 5 타깃 (Core + Kit library + executable + 2 testTarget) | ✅ |

---

## 4. Incomplete Items

### 4.1 Carried Over to Next Cycle

| Item | Reason | Priority | Estimated Effort |
|------|--------|----------|------------------|
| 커밋·태그(v0.3.0) | 현재 작업 트리 미커밋 상태 | High | < 0.5일 |
| 코드 리뷰 Minor #4~#7 (Keychain 로깅, permissionTimer 토글, NSScreen 재계산, "Unknown" 비교) | 본 사이클 범위 외 | Low~Medium | 차기 |

### 4.2 Cancelled/On Hold Items

| Item | Reason | Alternative |
|------|--------|-------------|
| BLE 스캔 정책 변경 / `@Published devices` 발행 최적화 | Plan §2.2 Out of Scope | 차기 Phase |

---

## 5. Quality Metrics

### 5.1 Final Analysis Results

| Metric | Target | Final | Note |
|--------|--------|-------|------|
| Design Match Rate | 90% | 100% | Structural×0.2 + Functional×0.4 + Contract×0.4 |
| Structural Match | — | 100% | Design §11.1 파일 구조 일치 |
| Functional Depth | — | 100% | 플레이스홀더 없음, 전 분기 실로직 |
| Contract Match | — | 100% | Option B / 순수 decide / prune 연동 모두 준수 |
| 단위+통합 테스트 | 통과 | 33/33 통과 | `Test run with 33 tests in 5 suites passed` |
| Release 빌드 | 통과 | `Build complete!` | `.build/release/AutoLock` Mach-O arm64 |
| Critical/Major Gap | 0 | 0 | iterate 불필요 |

### 5.2 Resolved Issues (코드 리뷰 2026-05-29)

| Issue | Resolution | Result |
|-------|------------|--------|
| 🔴 8초 프루닝이 stale/absence 분기를 죽은 코드로 만듦 | 프루닝 임계값을 `absencePointSeconds + pruneMarginSeconds`로 grace 연동 | ✅ 해결 — 분기 도달성 전수 증명 |
| 🟠 평가 타이머 `.default` 모드 → 메뉴 트래킹 중 정지 가능 | `RunLoop.main.add(timer, forMode: .common)` 등록 | ✅ 해결 |
| 🟠 토글 OFF 시 BLE 스캔 미정지 | `$enabled` sink에 `else { stopScanning() }` 추가 | ✅ 해결 |

---

## 6. Lessons Learned & Retrospective

### 6.1 What Went Well (Keep)

- 코드 리뷰 → Plan 편입 흐름이 명확했고, 세 결함이 동일 근본원인(시간 상수 분산)으로 묶여 단일 출처화 하나로 동시 해소됨.
- 핵심 불변식(`pruneAfterSeconds > absencePointSeconds`)을 grace 전 구간 전수 테스트로 고정해, "도달 가능성"이라는 추상 명제를 실증 가능한 형태로 변환함.
- Option B(완전 분리)로 CoreBluetooth 무의존 순수 도메인을 확보 → `@main` 충돌 없이 swift-testing 실행 경로 확립.

### 6.2 What Needs Improvement (Problem)

- 시간 상수가 두 모듈에 흩어진 채 누적된 것이 결함의 근원 — 초기 설계 시 "사라짐" 판정의 단일 출처가 없었음.
- Xcode 부재 환경에서 swift-testing 실행에 rpath 수동 지정(`scripts/test.sh`)이 필요했음 — 테스트 인프라가 사전에 표준화돼 있지 않았음.

### 6.3 What to Try Next (Try)

- 새 시간/임계값 상수는 반드시 `LockTuning`에서 도출하고, 상호 불변식이 있으면 즉시 전수 테스트로 고정.
- 차기 사이클에서 코드 리뷰 Minor 항목(permissionTimer 토글 등)을 묶어 v0.3.0 Phase 후속으로 처리.

---

## 7. Process Improvement Suggestions

### 7.1 PDCA Process

| Phase | Current | Improvement Suggestion |
|-------|---------|------------------------|
| Plan | 코드 리뷰 발(發) — PRD 단계 생략 | 핫픽스성 사이클은 현행 유지가 적절 |
| Design | Option B 선택이 테스트 인프라까지 결정 | 유지 |
| Do | 테스트 rpath 우회 스크립트 수작업 | `scripts/test.sh` 표준화 완료 — 재사용 |
| Check | 네이티브 → 정적+단위테스트로 대체 | 웹 L1/L2/L3 미적용 정당 |

### 7.2 Tools/Environment

| Area | Improvement Suggestion | Expected Benefit |
|------|------------------------|------------------|
| CI | `scripts/test.sh`를 CI에 연결 | 회귀 자동 차단 |
| 커밋 | 본 변경 커밋·v0.3.0 태깅 | 배포 추적성 확보 |

---

## 8. Next Steps

### 8.1 Immediate

- [ ] 변경사항 커밋 (현재 미커밋) — 한글 커밋 메시지로 v0.3.0 Phase 1 기록
- [ ] v0.3.0 ad-hoc 서명 릴리스 빌드 검증

### 8.2 Next PDCA Cycle

| Item | Priority | Note |
|------|----------|------|
| 코드 리뷰 Minor #4~#7 처리 | Medium | permissionTimer 토글, Keychain 로깅 등 |
| BLE 스캔 정책 / 발행 최적화 | Low | 본 사이클 Out of Scope |

---

## 9. Changelog

### v0.3.0 Phase 1 (2026-06-01, 커밋 대기 중)

**Added:**
- `AutoLockCore` 순수 도메인 라이브러리 타깃 (Foundation only)
- `ProximityEvaluator.decide()` 순수 판정 함수
- `LockTuning.absencePointSeconds` / `pruneAfterSeconds` (grace 연동 단일 출처)
- `Tests/AutoLockCoreTests/` swift-testing 12 케이스 + `scripts/test.sh`

**Changed:**
- 도메인 타입(`ProximityState`/`LockReason`/`ControllerStatus`/`TrackedDevice`/`DiscoveredDevice`/`LockTuning`)을 `AutoLockCore`로 이전, `public` 부여
- `ProximityController`가 `ProximityEvaluator`에 판정 위임, 평가 타이머 `.common` 모드 등록
- `BLEScanner.clearStale`가 고정 8초 → grace 연동 `pruneAfterSeconds` 사용

**Fixed:**
- stale/absence 즉시잠금 분기 죽은 코드 복구 (Critical)
- 평가 타이머 `.default` → `.common` (메뉴 트래킹 중 평가 정지)
- 토글 OFF 시 BLE 스캔 미정지 (배터리 소모)

### v0.3.0 Phase 1 — 검증 심화 (2026-06-01, 커밋 대기 중)

> "정상 동작 확인" 요청에 따른 후속 리팩터링. 동작 변경 없음(구조만 변경), 회귀 차단 폭 확대.

**Added:**
- `AutoLockKit` 라이브러리 타깃 — 테스트 가능한 컨트롤러 계층 (executable의 `@main` import 제약 해소)
- 프로토콜 5종 `ProximityServices.swift` (`ScreenLocking`/`DisplayWaking`/`UnlockTriggering`/`OverlayPresenting`/`ProximityScanning`)
- 순수 함수 `BestDeviceSelector.select` / `WakeDecision.decide` + `UnlockOutcome` (AutoLockCore)
- `ProximityServiceAdapters.swift` — 시스템 API를 프로토콜에 맞추는 어댑터(`System*`)
- `Tests/AutoLockKitTests/` 통합 테스트 8건 (Fake/Spy 주입) + AutoLockCore 단위 테스트 +12건 (총 33건)

**Changed:**
- `ProximityController` 싱글톤 제거 → 생성자 주입(6 의존성). `AutoLockApp`가 조립 루트.
- `BLEScanner`/`Settings` `AutoLockKit`로 이전·public화, `Settings(defaults:)` 주입형 init
- PermissionPrompt 와이어링을 조립 루트(`AutoLockApp`)로 이동 (Published 관찰은 구체 타입 의존)
- `UnlockTrigger.Result` → `AutoLockCore.UnlockOutcome`로 통합
- `Package.swift` 3 → 5 타깃

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-06-01 | 완료 보고서 작성 (Match Rate 100%, 12/12 테스트 통과, 커밋 대기) | 주재만 |
| 1.1 | 2026-06-01 | 검증 심화 반영 — DI 리팩터링(AutoLockKit) + 통합 테스트 33건 + release 스모크 + 수동 E2E 체크리스트 | 주재만 |
