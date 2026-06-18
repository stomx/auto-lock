---
title: AutoLock 작업 핸드오프
project: AutoLock
status: in-progress
version: v0.3.0 배포 완료 · v0.3.1 결함수정 배치 구현 완료(미커밋)
updated: 2026-06-17
tags: [autolock, handoff, pdca, swift, macos, ble]
aliases: [핸드오프, HANDOFF, 이어서작업]
---

# 🔖 AutoLock 작업 핸드오프

> [!info] 이 노트의 목적
> 다른 디바이스에서 작업을 **그대로 이어가기 위한 단일 진입점**.
> 이 노트 하나만 열면 "지금까지 뭐 했고, 상태가 어떻고, 다음에 뭘 해야 하는지"가 복원됩니다.
> 작업 재개 시: 이 노트 → 관련 문서(아래 위키링크) 순으로 읽으면 됩니다.

## 한 줄 요약

BLE RSSI 기반 macOS 메뉴바 자동 잠금 앱. v0.3.0(3계층 분리 + 테스트 인프라) 배포 완료. 직전 작업은 **독립 에이전트(codex) 교차검증 코드 리뷰 → 발견 결함 다수를 TDD로 수정**(v0.3.1 결함수정 배치). **구현·검증 완료, 미커밋 상태**(커밋은 명시 요청 시에만 규칙).

---

## 📍 현재 상태 (2026-06-18 기준)

| 항목 | 상태 |
|------|------|
| 기능 구현 | ✅ 3계층(Core/Kit/AutoLock) + DI. v0.3.1 결함수정 배치 반영 |
| 자동 테스트 | ✅ **104건** 전부 통과 (`./scripts/test.sh`) |
| 빌드 | ✅ debug + release + `-strict-concurrency=complete` 통과(경고는 의도된 SecKeychain deprecation 4건만) |
| 앱 패키징 | ✅ `./build_app.sh` 통과 |
| **Git 커밋·푸시** | ✅ **v0.3.1 커밋·푸시 완료** — `origin/main` 반영 |
| **GitHub 릴리스** | ✅ **v0.3.1 배포** — DMG/ZIP/체크섬 업로드 |
| 옵시디언 동기화 | Obsidian Sync (이 폴더가 vault) |

> [!success] v0.3.0 커밋·푸시·배포 완료 (2026-06-02)
> 5개 논리 커밋(`5a6d747`~`8527035`)으로 push 완료, GitHub 릴리스 v0.3.0 생성.
> → https://github.com/stomx/auto-lock/releases/tag/v0.3.0

> [!success] v0.3.1 결함수정 배치 커밋·푸시·배포 완료 (2026-06-18)
> codex 교차검증으로 발견한 결함을 TDD로 수정. 자세한 변경은 루트
> [CHANGELOG.md](../CHANGELOG.md) `[0.3.1]` 참조. 신규 순수 타입(Core):
> RssiSmoother / UnlockPreflight / UnlockFollowup / CStringSafe / KeychainACLPolicy /
> ScanPolicy / DeviceNameResolver / LockSettingBounds / MonotonicClock. MenuView
> 896→501줄 3분할. Settings·BLEScanner @MainActor 격리.
> → https://github.com/stomx/auto-lock/releases/tag/v0.3.1

---

## 🧭 코드 품질·커버리지 재평가 (2026-06-02 기준, 대부분 이후 해소됨)

> [!note] 아래는 v0.3.0 직후 평가 기록이다. 여기서 지적된 Major 3건과 무테스트
> 사각지대 상당수는 **v0.3.1 결함수정 배치(2026-06-17)에서 해소**됐다. 현재 테스트
> 104건, MenuView 분할 완료, 잠금실패 통보 추가 등. 이력으로 보존한다.

사용자 질문: "Clean Code로 잘 작성됐나? TDD 커버리지 100%인가?"
→ 독립 에이전트 2개(verifier + code-reviewer)로 실측·정독 평가. **결론(당시): 둘 다 "부분적", 100% 아님.**

### Clean Code: 7.5 / 10 (부분적)

| 계층 | 점수 | 평가 |
|------|:----:|------|
| AutoLockCore / AutoLockKit | 9/10 | DI·순수함수·ISP·테스트 모범적 |
| AutoLock (UI·조립·시스템API) | 6/10 | God File, 매핑 중복, 숨은 의존성 |

**주요 결함 (Major 3건) — 해소 현황:**
- [x] **God File** — `MenuView.swift` 896줄 → 501줄 + `DesignSystem`/`DevicePickerView`/`PasswordSheetView` 3분할 완료 (v0.3.1)
- [ ] **상태→표현 매핑 중복** — `ProximityState` switch 분산 (OCP). 미해소(저위험, 후속 후보)
- [x] **숨은 전역 의존성** — `Settings.shared`/`BLEScanner` `@MainActor` 격리로 동시성 안전화(v0.3.1). UI의 구체타입 직접 호출은 일부 잔존

**Minor 해소:** 잠금 실패 시 사용자 무통보 → `ControllerStatus.lockFailed`로 통보(v0.3.1). 강제 언래핑은 안전 보장 확인됨.

> Critical·보안 결함 **없음**. 강제 언래핑 2건 모두 안전 보장됨.

### TDD 커버리지 (당시 ~40% → v0.3.1에서 대폭 상승)

당시 사각지대였던 위험 로직은 **순수 타입으로 추출해 테스트**로 덮었다(테스트 37→104건):
- `KeychainStore`(ACL 판정) → `KeychainACLPolicy`[테스트]
- `UnlockTrigger`(자동해제 게이팅/후속) → `UnlockPreflight`·`UnlockFollowup`[테스트]
- `BLEScanner` EWMA·이름해석·스캔정책 → `RssiSmoother`·`DeviceNameResolver`·`ScanPolicy`[테스트]
- `ScreenLocker` `dlerror()` → `CStringSafe`[테스트]

> [!note] 남은 사각지대
> 시스템 계층 자체(실제 CoreBluetooth 콜백 배선, NSWindow/IME, CGEvent 합성)는
> 헤드리스 단위 테스트가 구조적으로 불가능 — 순수 로직 추출 + 회귀(빌드/기존 테스트)
> + `diagnose` CLI 수동 점검으로 보완한다.

---

## ✅ 다음 할 일 (우선순위)

> v0.3.1 결함수정 배치는 **커밋·푸시·릴리스 완료**. 남은 것은 선택적 후속 개선.

1. [ ] (선택) **상태→표현 매핑 단일화** — `ProximityState` switch 중복 통합 (OCP, 저위험)
2. [ ] (선택) 수동 E2E 체크리스트 실기기 수행 → [[proximity-timing-fix.e2e-manual]]
3. [ ] (선택) SecKeychain deprecation 4건 — modern data-protection keychain 전환은 정식 서명(entitlement) 필요

**v0.3.1에서 해소 완료(이력):**
- [x] `MenuView.swift` 3분할
- [x] 위험 로직(Keychain ACL/자동해제/EWMA/dlerror) 순수 타입 추출 + 테스트
- [x] 잠금 실패 통보(`ControllerStatus.lockFailed`)
- [x] `Settings`/`BLEScanner` `@MainActor` 격리(Swift6 동시성)
- [x] wall-clock → `MonotonicClock`, 거리 임계값 기본 -80dBm
- [x] ~~v0.3.1 커밋·푸시·릴리스 배포~~ · ~~v0.3.0 커밋·푸시·배포~~

---

## 🔗 관련 문서 (위키링크)

### 프롬프트 히스토리
- [[prompt-history]] — 요약본 (In + 응답 첫 문장, 108건)
- [[prompt-history-full]] — 전문 (응답 전체, 145K자)

### PDCA 사이클: proximity-timing-fix
- [[proximity-timing-fix.plan]] — Plan
- [[proximity-timing-fix.design]] — Design (Option B 완전 분리)
- [[proximity-timing-fix.analysis]] — Check (Match Rate 100%)
- [[proximity-timing-fix.report]] — 완료 보고서 (37 테스트, 미커밋)
- [[proximity-timing-fix.e2e-manual]] — 수동 E2E 체크리스트 8건
- [[code-review-2026-05-29]] — 사이클 트리거 코드리뷰

### 프로젝트 현황
- [[PROJECT_STATUS]] — 전체 현황
- [[v0.3.0-phase1-2]] — Phase 계획

---

## 🏗️ 아키텍처 빠른 참조

```
Sources/
├── AutoLockCore/   순수 도메인 (Foundation only) — LockTuning, ProximityEvaluator,
│                    BestDeviceSelector, WakeDecision, ProximityTypes, Devices, UnlockOutcome,
│                    RssiSmoother, UnlockPreflight, UnlockFollowup, CStringSafe,
│                    KeychainACLPolicy, ScanPolicy, DeviceNameResolver, LockSettingBounds, MonotonicClock
├── AutoLockKit/    컨트롤러 계층(@MainActor) — ProximityController, BLEScanner, Settings,
│                    ProximityServices(프로토콜 5종)
└── AutoLock/       조립 루트 + UI — AutoLockApp, ProximityServiceAdapters, MenuView,
                     DesignSystem, DevicePickerView, PasswordSheetView, PasswordWindow,
                     PickerWindow, CountdownOverlay, ScreenLocker, UnlockTrigger,
                     KeychainStore, Diagnostics, main.swift
Tests/  (총 104건)
├── AutoLockCoreTests/   순수 도메인 단위 테스트 (76건)
└── AutoLockKitTests/    ProximityController(배선)·ProximityTimeline(리플레이)·Settings (28건)
```

**핵심 불변식**: `pruneAfterSeconds = absencePointSeconds + pruneMarginSeconds` → 잠금 발화 시점에 기기가 아직 맵에 존재 (stale 분기 도달 가능). `LockTuning.swift`가 단일 출처.

**테스트 실행**: `./scripts/test.sh` (Xcode 없음 → swift-testing dylib rpath 수동 지정)

---

## 📌 고정 규칙 (사용자 지시)

- 모든 설명·커밋 메시지 **한글**
- UI 라벨 한글, Pretendard 단일 폰트
- 추측성 fallback 레이어 회피 → 근본원인 진단 후 단일 해결책
- 커밋·푸시는 **명시적 요청 시에만**
- 비용 우선: 무거운 작업은 서브에이전트 위임
