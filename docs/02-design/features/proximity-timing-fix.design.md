---
template: design
version: 1.3
feature: proximity-timing-fix
project: AutoLock
date: 2026-05-29
author: 주재만
status: Draft
---

# proximity-timing-fix Design Document

> **Summary**: 순수 도메인 로직을 `AutoLockCore` 라이브러리 타깃으로 완전 분리하고, 그 안에 시간 판정을 담당하는 `ProximityEvaluator` 순수 함수를 신설하여 3개 결함을 수정·검증한다.
>
> **Project**: AutoLock
> **Version**: v0.3.0 (Phase 1)
> **Author**: 주재만
> **Date**: 2026-05-29
> **Status**: Draft
> **Planning Doc**: [proximity-timing-fix.plan.md](../01-plan/features/proximity-timing-fix.plan.md)

---

## Context Anchor

| Key | Value |
|-----|-------|
| **WHY** | 시간 상수가 두 모듈에 흩어져 충돌 → 핵심 잠금 분기가 죽은 코드가 되고, 타이머 모드/스캔 수명 관리가 어긋남 |
| **WHO** | AutoLock 사용자(자리를 비울 때 Mac이 자동으로 잠기기를 기대) |
| **RISK** | 프루닝 임계값을 잘못 연동하면 디바이스 메모리 누적 또는 잠금 지연. 타이머 모드 변경이 평가 빈도에 영향 |
| **SUCCESS** | stale/absence 분기가 실제로 도달 가능해짐(단위 테스트로 증명), `.common` 타이머 등록 확인, OFF 시 `isScanning == false`, `swift build`/`swift test` 통과 |
| **SCOPE** | Phase 1: 3개 결함 수정 + 도메인 로직 라이브러리 분리. Phase 2: 순수 단위 테스트 |

---

## 1. Overview

### 1.1 Design Goals

- 시간 판정의 **단일 출처화**: "사라짐"을 결정하는 모든 시간 상수를 `LockTuning` 한 곳에서 도출하고, 프루닝이 그 판정을 죽이지 않게 한다.
- **테스트 가능성**: CoreBluetooth/타이머/시스템 호출과 분리된 순수 결정 로직을 라이브러리 타깃에 두어 `@main` 충돌 없이 XCTest로 검증한다.
- **부수효과 격리**: 화면 잠금·스캔 제어·타이머 같은 부수효과는 `ProximityController`(executable)에 잔류, 결정은 `ProximityEvaluator`(core)에 위임.

### 1.2 Design Principles

- 순수 함수: `ProximityEvaluator`는 입력(스냅샷)만으로 결정을 반환 — 시간/IO 부수효과 없음
- 단일 책임: 컨트롤러는 오케스트레이션, Evaluator는 판정, Scanner는 BLE
- 의존성 역전: executable → core 단방향. core는 외부 무의존(Foundation만)

---

## 2. Architecture Options

### 2.0 Architecture Comparison

| Criteria | Option A: Minimal | Option B: Clean | Option C: Pragmatic |
|----------|:-:|:-:|:-:|
| **Approach** | executable + `@testable import` | 도메인 전체 core 이전 | 순수 로직만 core 추출 |
| **New Files** | 2 | 2 | 2 |
| **Moved Files** | 0 | 5~6 | 1 |
| **Complexity** | Low | High | Medium |
| **Maintainability** | Medium | High | High |
| **Test Reliability** | Low (`@main` 취약) | High | High |
| **Risk** | 링커/`@main` 충돌 | import 변경 광범위 | Low |
| **Recommendation** | 핫픽스 | 장기 대형 | 기본값 |

**Selected**: **Option B — Clean** — **Rationale**: 사용자 선택. 도메인 값 타입(`ProximityState`/`LockReason`/`ControllerStatus`/`TrackedDevice`/`DiscoveredDevice`/`LockTuning`)이 모두 CoreBluetooth 무의존이라 안전하게 이전 가능하며, 향후 도메인 확장·테스트 자산이 누적될 기반을 마련한다.

### 2.1 Target Structure (SwiftPM)

```
Package.swift
├── target: AutoLockCore   (library)   ← 순수 도메인 + 결정 로직 (Foundation only)
│     ProximityState, LockReason, ControllerStatus
│     TrackedDevice, DiscoveredDevice
│     LockTuning
│     ProximityEvaluator          (신규)
├── target: AutoLock       (executable) depends: AutoLockCore
│     ProximityController, BLEScanner, Settings, ScreenLocker,
│     UnlockTrigger, MenuView, ... (UI/BLE/시스템 호출)
└── testTarget: AutoLockCoreTests   depends: AutoLockCore   (신규)
      ProximityEvaluatorTests, LockTuningTests
```

### 2.2 Data Flow (수정 후)

```
BLEScanner.didDiscover ──(devices[id] 갱신)──▶ devices[UUID:DiscoveredDevice]
                                                      │
            prune timer(2s, 임계값=LockTuning.pruneAfter)│  ← FR-01: grace 연동
                                                      ▼
evaluationTimer(1Hz, .common) ──▶ ProximityController.evaluate()  ← FR-03: .common
        │  best = devices에서 tracked 최대 RSSI
        ▼
ProximityEvaluator.decide(snapshot) ──▶ Decision(state, status, action)  ← 순수
        │
        ▼  (부수효과 적용)
   ScreenLocker.lock() / CountdownOverlay / DisplayWaker / UnlockTrigger

Settings.$enabled == false ──▶ scanner.stopScanning()  ← FR-04
```

### 2.3 Dependencies

| Component | Depends On | Purpose |
|-----------|-----------|---------|
| `AutoLock` (exe) | `AutoLockCore` | 도메인 타입·결정 로직 사용 |
| `ProximityController` | `ProximityEvaluator`, `BLEScanner`, `LockTuning` | 평가 오케스트레이션 |
| `ProximityEvaluator` | (Foundation only) | 순수 시간/신호 판정 |
| `AutoLockCoreTests` | `AutoLockCore` | 순수 로직 검증 |

---

## 3. Data Model

### 3.1 신규: ProximityEvaluator 입력/출력

```swift
// AutoLockCore — 순수, Foundation only
public struct ProximitySnapshot {
    public let now: Date
    public let best: BestDevice?        // 추적 디바이스 중 최강 신호 (없으면 nil)
    public let rssiThreshold: Int       // settings.rssiThreshold (음수)
    public let definitiveAwayThreshold: Int
    public let gracePeriodSeconds: Int
    public let awaySince: Date?         // 현재 away 사이클 시작 시각

    public struct BestDevice {
        public let id: UUID
        public let smoothedRssi: Double
        public let lastSeen: Date
    }
}

public struct ProximityDecision: Equatable {
    public let state: ProximityState
    public let status: ControllerStatus
    public let action: Action          // 부수효과 지시 (컨트롤러가 실행)
    public let awaySince: Date?         // 갱신된 away 시작 (컨트롤러가 반영)

    public enum Action: Equatable {
        case none                       // 상태만 반영
        case watching                   // near — 화면 깨우기 검토
        case showOverlay(until: Date)   // grace 카운트다운 최종 구간
        case hideOverlay
        case lock(reason: LockReason)   // 잠금 실행
    }
}
```

> `ProximityState`/`LockReason`/`ControllerStatus`는 기존 정의를 그대로 `AutoLockCore`로 이전(시그니처 불변, `public` 부여).

### 3.2 이전 대상 타입 (정의 위치 변경, 내용 불변)

| Type | 현재 위치 | 이전 후 | 비고 |
|------|-----------|---------|------|
| `ProximityState` | ProximityController.swift:5 | AutoLockCore | `public` 부여 |
| `LockReason` | ProximityController.swift:15 | AutoLockCore | `public`, `logDescription` 유지 |
| `ControllerStatus` | ProximityController.swift:35 | AutoLockCore | `public` |
| `TrackedDevice` | Settings.swift:4 | AutoLockCore | `public`, Codable 유지 |
| `DiscoveredDevice` | BLEScanner.swift:5 | AutoLockCore | `public`, CoreBluetooth 무의존 확인됨 |
| `LockTuning` | LockTuning.swift | AutoLockCore | `public`, 프루닝 상수 추가 |

---

## 4. 핵심 로직 설계

### 4.1 FR-01: 프루닝-grace 연동 (Critical)

**문제**: `clearStale(olderThan: 8)` 고정 8초 < grace 하한 15초 → stale/absence 분기 사망.

**설계**: `LockTuning`에 프루닝 시간을 grace 기반으로 도출하는 규칙 추가. 프루닝은 absence 판정보다 **마진만큼 길게** 두어, absence 즉시잠금이 판정된 직후 정리되도록 한다.

```swift
// LockTuning (AutoLockCore)
/// 프루닝은 absence(즉시 잠금) 판정 시점보다 이만큼 더 늦게 일어나야
/// stale/absence 분기가 실제로 도달 가능하다. (마진 = 2 * evaluationInterval)
static let pruneMarginSeconds: TimeInterval = 2.0

/// grace 기반 프루닝 임계값. clearStale가 이 값을 사용한다.
static func pruneAfterSeconds(gracePeriodSeconds: Int) -> TimeInterval {
    Double(gracePeriodSeconds) * absenceMultiplier + pruneMarginSeconds
}
```

- `BLEScanner.clearStale`는 고정 8초 대신 `pruneAfterSeconds(grace)`를 사용 (grace는 호출 시 주입).
- 검증: grace=15 → absence=30s, prune=32s. `age`가 15s(stale 카운트다운)·30s(즉시 잠금)에 도달하기 전 디바이스가 살아있음 → 두 분기 도달 가능.

### 4.2 FR-02: stale/absence 분기 도달성

`ProximityEvaluator.decide`가 기존 `evaluate()`의 분기 로직을 그대로 순수화:

```
age = now - best.lastSeen
if age > grace * absenceMultiplier      → lock(.signalStaleSeconds(age))   // 즉시
else if age > grace                     → away 진입, reason=.signalStaleSeconds(age)
else if best.rssi <= definitiveAway     → lock(.signalCrashed)
else if best.rssi >= threshold          → watching (near)
else                                    → away 진입, reason=.signalWeak
best == nil                             → away 진입, reason=.deviceUnseen
```

away 진입 시 grace 카운트다운/오버레이/즉시잠금 판정도 순수 계산으로 반환(`Action`).

### 4.3 FR-03: 평가 타이머 `.common` 모드 (Major)

```swift
// ProximityController.init — 변경 전: Timer.scheduledTimer (.default)
let timer = Timer(timeInterval: LockTuning.evaluationIntervalSeconds, repeats: true) { [weak self] _ in
    Task { @MainActor in self?.evaluate() }
}
RunLoop.main.add(timer, forMode: .common)   // CountdownOverlay와 동일 패턴
evaluationTimer = timer
```

### 4.4 FR-04: 토글 OFF 시 스캔 정지 (Major)

```swift
// ProximityController.init — $enabled sink
settings.$enabled.sink { [weak self] enabled in
    guard let self else { return }
    if enabled { self.scanner.startScanning() }
    else       { self.scanner.stopScanning() }   // 추가
    self.status = enabled ? .watching : .idle
}
```

`BLEScanner.stopScanning()`은 이미 존재(스캔 중지 + prune timer 무효화). 호출만 연결.

---

## 6. Error Handling

| 상황 | 처리 |
|------|------|
| `best == nil` (디바이스 미감지) | `decide`가 `.deviceUnseen` away 경로 반환 (기존 동작 보존) |
| grace 경과 후 이미 잠김 | `ScreenLocker.isScreenLocked()` 확인 후 잠금 (기존 가드 유지) |
| 프루닝으로 디바이스 제거 직후 평가 | `best == nil` 경로 — `deviceUnseen`이 아닌 stale 잠금이 prune 전에 선행됨 |

---

## 8. Test Plan

> 본 기능은 네이티브 로직 — 웹 L1/L2/L3 대신 **순수 단위 테스트(XCTest)** 로 대체.

### 8.1 Test Scope

| Type | Target | Tool | Phase |
|------|--------|------|-------|
| Unit: 임계값 도출 | `LockTuning.pruneAfterSeconds` | XCTest | Do |
| Unit: 결정 로직 | `ProximityEvaluator.decide` | XCTest | Do |
| Characterization | 분리 전후 동일 입력→동일 전이 | XCTest | Do |

### 8.2 Unit Test Scenarios

| # | Target | 입력 | 기대 |
|---|--------|------|------|
| 1 | `pruneAfterSeconds` | grace=15 | 32.0 (15*2+2) |
| 2 | `pruneAfterSeconds` | grace=60 | 122.0 |
| 3 | `decide` (stale 즉시) | age=31s, grace=15 | `.lock(.signalStaleSeconds(31))` |
| 4 | `decide` (stale 카운트다운) | age=20s, grace=15 | away, `.signalStaleSeconds(20)` |
| 5 | `decide` (signalCrashed) | rssi=-95, definitiveAway=-90 | `.lock(.signalCrashed)` |
| 6 | `decide` (near) | rssi=-50, threshold=-70 | `watching`, state=.near |
| 7 | `decide` (signalWeak) | rssi=-75, threshold=-70 | away, `.signalWeak` |
| 8 | `decide` (deviceUnseen) | best=nil | away, `.deviceUnseen` |
| 9 | `decide` (grace 경과 잠금) | awaySince + grace < now | `.lock` |
| 10 | `decide` (오버레이 구간) | remaining ≤ 5s | `.showOverlay(until:)` |
| 11 | **도달성 증명** | prune=32 > absence=30 | stale/absence 분기가 prune 전 도달 |

### 8.3 Seed Data

해당 없음 (순수 함수, 입력 구조체 직접 구성).

---

## 9. Clean Architecture

### 9.1 Layer Structure

| Layer | Responsibility | Location |
|-------|---------------|----------|
| **Domain** | 값 타입, 시간/신호 판정 (순수) | `Sources/AutoLockCore/` |
| **Application** | 평가 오케스트레이션, 부수효과 적용 | `ProximityController` |
| **Infrastructure** | BLE, 화면잠금, 키입력, 키체인 | `BLEScanner`, `ScreenLocker`, `UnlockTrigger`, `KeychainStore` |
| **Presentation** | 메뉴/오버레이/창 | `MenuView`, `CountdownOverlay`, `*Window` |

### 9.2 Dependency Rules

```
Presentation ──▶ Application ──▶ Domain(AutoLockCore) ◀── Infrastructure
Rule: AutoLockCore는 외부 무의존 (Foundation only). 안쪽이 바깥을 import하지 않음.
```

### 9.4 This Feature's Layer Assignment

| Component | Layer | Location |
|-----------|-------|----------|
| `ProximityEvaluator` (신규) | Domain | `Sources/AutoLockCore/ProximityEvaluator.swift` |
| `ProximityState`/`LockReason`/`ControllerStatus` | Domain | `Sources/AutoLockCore/ProximityTypes.swift` |
| `TrackedDevice`/`DiscoveredDevice` | Domain | `Sources/AutoLockCore/Devices.swift` |
| `LockTuning` | Domain | `Sources/AutoLockCore/LockTuning.swift` |
| `ProximityController` | Application | `Sources/AutoLock/ProximityController.swift` |

---

## 11. Implementation Guide

### 11.1 File Structure (변경 후)

```
Package.swift                          (수정: 3 타깃)
Sources/
├── AutoLockCore/                      (신규 라이브러리)
│   ├── LockTuning.swift               (이동 + pruneAfterSeconds 추가)
│   ├── ProximityTypes.swift           (이동: State/Reason/Status)
│   ├── Devices.swift                  (이동: TrackedDevice/DiscoveredDevice)
│   └── ProximityEvaluator.swift       (신규: decide)
└── AutoLock/                          (executable, AutoLockCore import)
    ├── ProximityController.swift      (수정: Evaluator 위임, 타이머, stopScanning)
    ├── BLEScanner.swift               (수정: clearStale grace 연동, 타입 import)
    ├── Settings.swift                 (수정: TrackedDevice import)
    └── ... (import AutoLockCore 추가)
Tests/
└── AutoLockCoreTests/                 (신규)
    ├── ProximityEvaluatorTests.swift
    └── LockTuningTests.swift
```

### 11.2 Implementation Order

1. [ ] `Package.swift`에 `AutoLockCore` 라이브러리 + `AutoLockCoreTests` 테스트 타깃 추가, `AutoLock`이 `AutoLockCore` 의존
2. [ ] 도메인 타입 이전 (`ProximityTypes`/`Devices`/`LockTuning`), `public` 부여 — 빌드 통과 확인
3. [ ] `LockTuning.pruneAfterSeconds` 추가 (FR-01)
4. [ ] `ProximityEvaluator.decide` 신규 — 기존 `evaluate()` 분기 순수 이식 (FR-02)
5. [ ] `ProximityController.evaluate()`가 `decide` 위임하도록 리팩터 + 부수효과 적용
6. [ ] 평가 타이머 `.common` 등록 (FR-03)
7. [ ] `$enabled` sink에 `stopScanning()` 연결 (FR-04)
8. [ ] `BLEScanner.clearStale`가 grace 연동 임계값 사용
9. [ ] `AutoLockCoreTests` 작성 (FR-05) — §8.2 11개 케이스
10. [ ] `swift build` + `swift test` 통과 확인

### 11.3 Session Guide

#### Module Map

| Module | Scope Key | Description | Estimated Turns |
|--------|-----------|-------------|:---------------:|
| Core 분리 | `module-1` | 타깃 구성 + 도메인 타입 이전 + 빌드 복구 | 15-20 |
| 결정 로직 | `module-2` | Evaluator 신설 + 컨트롤러 위임 + 3개 결함 수정 | 20-25 |
| 테스트 | `module-3` | XCTest 11 케이스 + 도달성 증명 | 15-20 |

#### Recommended Session Plan

| Session | Phase | Scope | Turns |
|---------|-------|-------|:-----:|
| Session 1 | Do | `--scope module-1,module-2` | 35-45 |
| Session 2 | Do + Check | `--scope module-3` + analyze | 30-40 |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-05-29 | 초안 (Option B Clean 선택) | 주재만 |
