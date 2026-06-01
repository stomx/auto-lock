---
template: plan
version: 1.3
feature: proximity-timing-fix
project: AutoLock
date: 2026-05-29
author: 주재만
status: Draft
---

# proximity-timing-fix Planning Document

> **Summary**: 근접 판정 상태머신의 시간 기반 결함 3건(프루닝-grace 충돌, 평가 타이머 RunLoop 모드, 토글 OFF 시 스캔 미정지)을 수정하고, 시간 판정 로직을 순수 단위 테스트로 검증한다.
>
> **Project**: AutoLock (BLE RSSI 기반 macOS 메뉴바 자동 잠금)
> **Version**: v0.2.1 → v0.3.0 (Phase 1)
> **Author**: 주재만
> **Date**: 2026-05-29
> **Status**: Draft

---

## Executive Summary

| Perspective | Content |
|-------------|---------|
| **Problem** | `BLEScanner`의 8초 프루닝이 `gracePeriodSeconds`(하한 15초)보다 짧아, `ProximityController.evaluate()`의 stale/absence 잠금 분기가 절대 도달 불가능한 죽은 코드가 됨. 또한 평가 타이머가 `.default` RunLoop 모드라 UI 트래킹 중 정지 가능하고, 토글 OFF 시에도 BLE 스캔이 계속 돌아 배터리를 소모함. |
| **Solution** | "사라짐" 판정 시간 상수를 `LockTuning` 단일 출처로 일원화 — 프루닝 임계값을 `gracePeriodSeconds * absenceMultiplier`에 안전 마진을 더한 값으로 연동. 평가 타이머를 `.common` 모드로 등록. 토글 OFF 시 `stopScanning()` 호출. 시간 판정 로직을 BLE에서 분리해 XCTest로 검증. |
| **Function/UX Effect** | "신호 끊김 N초" 즉시 잠금/카운트다운이 의도대로 동작. 메뉴를 연 채 자리를 비워도 평가가 지속됨. 기능 OFF 시 배터리 소모 감소. 사용자 경험은 더 신뢰성 있는 자동 잠금. |
| **Core Value** | 자동 잠금의 핵심 안전 보장(자리를 비우면 반드시 잠긴다)을 결함 없이 작동시킨다. |

---

## Context Anchor

| Key | Value |
|-----|-------|
| **WHY** | 시간 상수가 두 모듈에 흩어져 충돌 → 핵심 잠금 분기가 죽은 코드가 되고, 타이머 모드/스캔 수명 관리가 어긋남 |
| **WHO** | AutoLock 사용자(자리를 비울 때 Mac이 자동으로 잠기기를 기대) |
| **RISK** | 프루닝 임계값을 잘못 연동하면 디바이스 메모리 누적 또는 잠금 지연. 타이머 모드 변경이 평가 빈도에 영향 |
| **SUCCESS** | stale/absence 분기가 실제로 도달 가능해짐(단위 테스트로 증명), `.common` 타이머 등록 확인, OFF 시 `isScanning == false`, `swift build` 통과 |
| **SCOPE** | Phase 1: 3개 결함 수정 + 시간 로직 분리. Phase 2: 순수 단위 테스트. (UI/스캔정책/발행최적화 제외) |

---

## 1. Overview

### 1.1 Purpose

근접 잠금 상태머신이 시간 기반 판정을 두 모듈(`BLEScanner` 프루닝, `ProximityController` 평가)에 나눠 갖고 있어 서로 충돌한다. 이를 단일 출처(`LockTuning`)로 일원화하여 의도한 잠금 시나리오가 모두 작동하도록 한다.

### 1.2 Background

2026-05-29 코드 리뷰(`docs/03-analysis/code-review-2026-05-29.md`)에서 Critical 1건, Major 2건이 발견되었다. 세 건 모두 `ProximityController`/`BLEScanner`의 시간·상태·리소스 수명 관리에 속한다.

### 1.3 Related Documents

- 코드 리뷰: `docs/03-analysis/code-review-2026-05-29.md`
- v0.3.0 Plan: `docs/plans/v0.3.0-phase1-2.md`

---

## 2. Scope

### 2.1 In Scope

- [ ] **결함 #1 (Critical)**: 프루닝 임계값을 grace 기반으로 연동 — stale/absence 분기 복구
- [ ] **결함 #2 (Major)**: `evaluationTimer`를 `.common` RunLoop 모드로 등록
- [ ] **결함 #3 (Major)**: `settings.enabled == false` 시 `scanner.stopScanning()` 호출
- [ ] 시간 판정 로직을 BLE 의존성에서 분리(순수 함수/타입)하여 테스트 가능화
- [ ] 순수 로직 XCTest 추가 (`Package.swift`에 테스트 타깃 구성)

### 2.2 Out of Scope

- BLE 스캔 정책 변경(active/passive, AllowDuplicates)
- `@Published devices` 발행 폭주 최적화
- UI/디자인 변경
- 신규 기능 추가

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-01 | 프루닝 임계값은 `gracePeriodSeconds`의 absence 판정 시간보다 길어, 디바이스가 stale·absence 판정 시점까지 `devices`에 잔존해야 함 | High | Pending |
| FR-02 | `evaluate()`의 `age > gracePeriodSeconds`(stale 카운트다운)와 `age > grace*absenceMultiplier`(즉시 잠금) 분기가 실제 도달 가능해야 함 | High | Pending |
| FR-03 | `evaluationTimer`가 `.common` RunLoop 모드로 등록되어 메뉴 트래킹 중에도 발화해야 함 | High | Pending |
| FR-04 | `settings.enabled`가 false로 바뀌면 `scanner.stopScanning()`이 호출되어 `isScanning == false`가 되어야 함 | Medium | Pending |
| FR-05 | 시간 판정(임계값 계산, 상태 전이)이 CoreBluetooth 없이 단위 테스트로 검증 가능해야 함 | Medium | Pending |

### 3.2 Non-Functional Requirements

| Category | Criteria | Measurement Method |
|----------|----------|-------------------|
| 정확성 | stale/absence 분기 도달 가능성 증명 | XCTest 단위 테스트 |
| 성능 | 평가 주기(1Hz)·메모리 사용 회귀 없음 | 빌드 + 수동 모니터링 |
| 호환성 | 기존 grace 카운트다운·오버레이 동작 보존 | 수동 검증 |

---

## 4. Success Criteria

### 4.1 Definition of Done

- [ ] FR-01~05 구현 완료
- [ ] 시간 판정 로직 단위 테스트 작성 및 통과
- [ ] stale/absence 분기 도달을 증명하는 테스트 케이스 존재
- [ ] `swift build` 및 `swift test` 통과

### 4.2 Quality Criteria

- [ ] 신규 lint/컴파일 경고 없음(기존 Keychain deprecation 제외)
- [ ] 빌드 성공
- [ ] code-review Critical 0건, Major 0건(재검토 시)

---

## 5. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| 프루닝 임계값을 grace에 연동 시 `devices` 메모리 누적 | Medium | Low | absence 판정 직후 prune되도록 마진을 작게(예: +2s) 유지 |
| 시간 로직 분리가 기존 동작을 미묘하게 바꿈 | High | Medium | 분리 전후 동일 입력→동일 전이를 테스트로 고정(characterization test) |
| `.common` 타이머가 UI 중 과도 발화 | Low | Low | 1Hz 유지, evaluate()는 멱등적이므로 영향 미미 |
| 테스트 타깃 추가가 기존 빌드 구성에 영향 | Medium | Low | 별도 test target으로 분리, 앱 타깃 의존성 미변경 |

---

## 6. Impact Analysis

### 6.1 Changed Resources

| Resource | Type | Change Description |
|----------|------|--------------------|
| `LockTuning` | Config(상수) | 프루닝 임계값 도출 규칙 추가 또는 `clearStale` 상수 일원화 |
| `BLEScanner.clearStale` / prune timer | Logic | 프루닝 임계값을 고정 8초 → grace 연동 값으로 변경 |
| `ProximityController` init | Logic | 평가 타이머 `.common` 등록, `$enabled` 구독에 `stopScanning()` 추가 |
| 시간 판정 로직 | 신규 분리 | `evaluate()`의 임계값/전이 판정을 순수 함수로 추출 |

### 6.2 Current Consumers

| Resource | Operation | Code Path | Impact |
|----------|-----------|-----------|--------|
| `clearStale` | 호출 | `BLEScanner.startPruneTimer` 2초 주기 | Needs verification — 임계값만 변경 |
| `devices` | READ | `ProximityController.evaluate` (best 선정) | None — 잔존 시간만 늘어남 |
| `devices` | READ | `MenuView.deviceRow` / `DevicePickerView.sortedDevices` | None |
| `evaluationTimer` | 생성 | `ProximityController.init` | Breaking(의도적) — 모드 변경 |
| `$enabled` | 구독 | `ProximityController.init` sink | None — else 분기만 추가 |

### 6.3 Verification

- [ ] 프루닝 임계값 변경이 디바이스 표시(MenuView)에 악영향 없음 확인
- [ ] grace 카운트다운·오버레이 기존 동작 유지 확인
- [ ] 타이머 모드 변경 후 평가 빈도 정상 확인

---

## 7. Architecture Considerations

> macOS 네이티브 SwiftUI 앱(SwiftPM). 웹/BaaS 템플릿 항목은 해당 없음.

### 7.1 핵심 설계 결정

| Decision | 선택 | Rationale |
|----------|------|-----------|
| 프루닝 전략 | grace 연동 (옵션 A) | 최소 변경으로 기존 grace/오버레이 동작 보존, `devices` 무한 증가 방지, EWMA 연속성 유지 |
| 시간 상수 위치 | `LockTuning` 단일 출처 | 흩어진 시간 판정을 한곳에 모아 충돌 재발 방지 |
| 테스트 전략 | 순수 로직 분리 + XCTest | CoreBluetooth 의존 없이 시간 판정 검증, v0.3.0 Phase 2와 부합 |
| 타이머 모드 | `Timer` + `RunLoop.main.add(_, forMode: .common)` | `CountdownOverlay`와 동일 패턴으로 통일 |

### 7.2 로직 분리 방향(Design 단계에서 확정)

`evaluate()` 내부의 "age/rssi → 상태·이유" 판정을 입력 구조체(현재 시각, lastSeen, smoothedRssi, 설정값)를 받아 결정(`ControllerStatus`/`LockReason` 또는 중간 enum)을 반환하는 순수 함수로 추출. CoreBluetooth·타이머·화면 잠금 같은 부수효과는 컨트롤러에 잔류.

---

## 8. Convention Prerequisites

### 8.1 기존 프로젝트 규약

- [x] Swift / SwiftPM (`Package.swift`)
- [x] 시간 상수 중앙화(`LockTuning`) 관행 존재
- [x] 도메인/프레젠테이션 분리(`LockReason`/`ControllerStatus`) 관행 존재
- [ ] 테스트 타깃 미존재 → 이번에 신규 도입

### 8.2 정의/확인할 규약

| Category | Current State | To Define | Priority |
|----------|---------------|-----------|:--------:|
| 테스트 디렉터리 구조 | missing | `Tests/AutoLockTests/` | High |
| 순수 로직 분리 경계 | partial | evaluate 판정부 추출 규칙 | High |
| 시간 상수 명명 | exists(LockTuning) | 프루닝 임계값 상수 추가 | Medium |

---

## 9. Next Steps

1. [ ] `/pdca design proximity-timing-fix` — 3개 아키텍처 안 비교 후 로직 분리 설계 확정
2. [ ] `/pdca do proximity-timing-fix` — 구현
3. [ ] `/pdca analyze proximity-timing-fix` — 갭 분석 + 테스트 실행

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-05-29 | 초안 (code-review 2026-05-29 기반) | 주재만 |
