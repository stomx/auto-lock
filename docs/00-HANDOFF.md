---
title: AutoLock 작업 핸드오프
project: AutoLock
status: in-progress
version: v0.3.0 (배포 완료, v0.3.1 후속 대기)
updated: 2026-06-02
tags: [autolock, handoff, pdca, swift, macos, ble]
aliases: [핸드오프, HANDOFF, 이어서작업]
---

# 🔖 AutoLock 작업 핸드오프

> [!info] 이 노트의 목적
> 다른 디바이스에서 작업을 **그대로 이어가기 위한 단일 진입점**.
> 이 노트 하나만 열면 "지금까지 뭐 했고, 상태가 어떻고, 다음에 뭘 해야 하는지"가 복원됩니다.
> 작업 재개 시: 이 노트 → 관련 문서(아래 위키링크) 순으로 읽으면 됩니다.

## 한 줄 요약

BLE RSSI 기반 macOS 메뉴바 자동 잠금 앱. v0.3.0 Phase 1(근접 타이밍 결함 수정 + 도메인 분리 + 테스트 인프라) **구현 완료, 전부 미커밋 상태**. 직전 작업은 **코드 품질·테스트 커버리지 정직한 재평가**.

---

## 📍 현재 상태 (2026-06-02 기준)

| 항목 | 상태 |
|------|------|
| 기능 구현 | ✅ v0.3.0 Phase 1 완료 (3계층 분리 + DI 리팩터링) |
| 자동 테스트 | ✅ 37건 전부 통과 (`./scripts/test.sh`) |
| 빌드 | ✅ debug + release 통과 |
| **Git 커밋·푸시** | ✅ **완료** — 5개 커밋 `origin/main` 반영 (2026-06-02) |
| **GitHub 릴리스** | ✅ **v0.3.0 배포** — DMG/ZIP/체크섬 업로드 |
| 옵시디언 동기화 | Obsidian Sync (이 폴더가 vault) |

> [!success] v0.3.0 커밋·푸시·배포 완료 (2026-06-02)
> 5개 논리 커밋(`5a6d747`~`8527035`)으로 push 완료, GitHub 릴리스 v0.3.0 생성.
> 원격 `Sources/`에 AutoLockCore/AutoLockKit 반영 확인, 태그 v0.3.0 존재.
> → https://github.com/stomx/auto-lock/releases/tag/v0.3.0
> 다른 기기에서 `git pull`로 코드까지 이어받을 수 있습니다.

---

## 🧭 직전 작업: 코드 품질·커버리지 재평가 결과

사용자 질문: "Clean Code로 잘 작성됐나? TDD 커버리지 100%인가?"
→ 독립 에이전트 2개(verifier + code-reviewer)로 실측·정독 평가. **결론: 둘 다 "부분적", 100% 아님.**

### Clean Code: 7.5 / 10 (부분적)

| 계층 | 점수 | 평가 |
|------|:----:|------|
| AutoLockCore / AutoLockKit | 9/10 | DI·순수함수·ISP·테스트 모범적 |
| AutoLock (UI·조립·시스템API) | 6/10 | God File, 매핑 중복, 숨은 의존성 |

**주요 결함 (Major 3건):**
- [ ] **God File** — `Sources/AutoLock/MenuView.swift` 896줄에 9개 타입 혼재 → 3분할 필요 (DesignTokens / DevicePickerView / PasswordSheetView)
- [ ] **상태→표현 매핑 중복** — `ProximityState` 4-케이스 switch가 3곳(`ProximityController.menuBarIcon:68`, `MenuView.stateAccent:542`, `MenuView.stateLabel:552`)에 흩어짐 (OCP 약점)
- [ ] **숨은 전역 의존성** — `Settings.shared` 싱글톤 + UI가 `KeychainStore`/`UnlockTrigger` 구체 타입 직접 호출 (DIP 누수)

**Minor:** 영속화 실패 묵살(`Settings.swift:50-55` `try?`), 매직넘버 `127`(BLEScanner) 미상수화, 강제 언래핑 2건(저위험), 잠금 실패 시 사용자 무통보.

> Critical·보안 결함 **없음**. 강제 언래핑 2건 모두 안전 보장됨.

### TDD 커버리지: 실측 ~40% (100% 아님)

| 타깃 | 총 파일 | 테스트 닿음 | 사각지대 |
|------|:----:|:----:|:----:|
| AutoLockCore | 7 | 7 | 0 |
| AutoLockKit | 4 | 3 | 1 (BLEScanner) |
| AutoLock (executable) | 14 | **0** | **14** |
| 합계 | 25 | 10 | **15 (60%)** |

> [!danger] 가장 위험한 코드가 전부 무테스트
> `KeychainStore`(암호/ACL), `ScreenLocker`(실제 잠금), `UnlockTrigger`(자동해제),
> `BLEScanner` CoreBluetooth 콜백(RSSI 필터·EWMA), `CountdownOverlay`, `PasswordWindow`(IME 차단), `Diagnostics`
> — AutoLock executable 타깃은 **테스트 타깃 자체가 없음**.

> [!note] "Match Rate 100%" ≠ 커버리지 100%
> 이전 PDCA 보고서의 100%는 **설계-구현 일치율**이지 코드 커버리지가 아님. 다른 지표.

---

## ✅ 다음 할 일 (우선순위)

> v0.3.0 커밋·푸시·배포는 **완료**(아래 ~~취소선~~). 남은 것은 v0.3.1 후속 품질 개선.
> 비용 대비 효과 순. TDD 모드면 "테스트 먼저 작성 → 실패 확인 → 구현" 순서로.

1. [ ] **`KeychainStore` 왕복 테스트** — 격리 service명으로 save→load→delete (저비용·고가치, 보안 핵심)
2. [ ] **`Settings.persistDevices` 영속화 왕복 테스트** — 이미 격리 UserDefaults 사용 → 거의 공짜
3. [ ] **`MenuView.swift` 3분할** — Clean Code Major 해소 (DesignTokens / DevicePickerView / PasswordSheetView)
4. [ ] **상태→표현 매핑 단일화** — `ProximityState` switch 중복 3곳 통합 (OCP)
5. [ ] **`Settings.shared` 싱글톤 정리** — DIP 누수 해소
6. [ ] (선택) 수동 E2E 체크리스트 실기기 수행 → [[proximity-timing-fix.e2e-manual]]
7. [x] ~~Git 커밋·푸시~~ — ✅ 완료 (6커밋, `00385ad`)
8. [x] ~~v0.3.0 릴리스 배포~~ — ✅ 완료 (DMG/ZIP/체크섬, GitHub Releases)

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
│                    BestDeviceSelector, WakeDecision, ProximityTypes, Devices, UnlockOutcome
├── AutoLockKit/    컨트롤러 계층 — ProximityController, BLEScanner, Settings,
│                    ProximityServices(프로토콜 5종)
└── AutoLock/       조립 루트 + UI — AutoLockApp, ProximityServiceAdapters, MenuView,
                     PasswordWindow, PickerWindow, CountdownOverlay, ScreenLocker,
                     UnlockTrigger, KeychainStore, Diagnostics, main.swift
Tests/
├── AutoLockCoreTests/   ProximityEvaluator/LockTuning/BestDeviceSelector/WakeDecision (25건)
└── AutoLockKitTests/    ProximityController(배선) + ProximityTimeline(가상기기 리플레이) (12건)
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
