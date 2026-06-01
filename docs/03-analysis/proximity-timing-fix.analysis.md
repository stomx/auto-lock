---
template: analysis
feature: proximity-timing-fix
project: AutoLock
date: 2026-06-01
author: 주재만
phase: check
---

# proximity-timing-fix Gap Analysis

> Design 문서 대비 구현 일치도 분석 (Check 단계)
> Design: [proximity-timing-fix.design.md](../02-design/features/proximity-timing-fix.design.md)
> Plan: [proximity-timing-fix.plan.md](../01-plan/features/proximity-timing-fix.plan.md)

## Context Anchor

| Key | Value |
|-----|-------|
| **WHY** | 시간 상수가 두 모듈에 흩어져 충돌 → 핵심 잠금 분기가 죽은 코드 |
| **WHO** | AutoLock 사용자(자리 비우면 자동 잠금 기대) |
| **RISK** | 프루닝 임계값 오연동 시 메모리 누적/잠금 지연 |
| **SUCCESS** | stale/absence 분기 도달 가능(테스트 증명), `.common` 타이머, OFF 시 스캔 정지, build/test 통과 |
| **SCOPE** | 3개 결함 + 도메인 라이브러리 분리 + 순수 단위 테스트 |

---

## 1. 검증 방식

웹 API가 아닌 macOS 네이티브 로직이므로 표준 L1/L2/L3(curl/Playwright) 대신:
- **정적 분석**: Design 구조/순서 ↔ 실제 코드 대조 (grep 증거)
- **런타임 검증**: swift-testing 12개 케이스 (Design §8.2) — `./scripts/test.sh`

## 2. 전략적 정합성 (Strategic Alignment)

| 질문 | 결과 |
|------|------|
| Plan의 핵심 문제(시간 상수 충돌)를 해결했는가? | ✅ `LockTuning.pruneAfterSeconds`로 단일 출처화 |
| 핵심 Design 결정(Option B Clean, 순수 Evaluator)을 따랐는가? | ✅ `AutoLockCore` 라이브러리 + `ProximityEvaluator.decide` 신설 |
| 결함 3건이 모두 코드에 반영되었는가? | ✅ FR-01~04 grep 증거 확인 |

## 3. Plan Success Criteria 평가

| FR | 기준 | 상태 | 증거 |
|----|------|------|------|
| FR-01 | 프루닝 임계값이 absence 판정보다 길다 | ✅ Met | `LockTuning.swift:58` pruneAfterSeconds = grace*2+2; `BLEScanner.swift:59` 사용; `pruneAlwaysOutlivesAbsencePoint` 테스트(grace 15~60 전수) |
| FR-02 | stale/absence 분기 도달 가능 | ✅ Met | `ProximityEvaluator.swift:83-97` 전 분기 이식; 테스트 #3·#4(stale), #5(crash), #6(near), #7(weak), #8(unseen), #9(grace 만료), #10(overlay) |
| FR-03 | 평가 타이머 `.common` 모드 | ✅ Met | `ProximityController.swift:37` `RunLoop.main.add(timer, forMode: .common)` |
| FR-04 | OFF 시 `stopScanning()` | ✅ Met | `ProximityController.swift:44` `else { self.scanner.stopScanning() }` |
| FR-05 | 순수 로직 단위 테스트 | ✅ Met | `Tests/AutoLockCoreTests/` 12 케이스, 전부 통과 |

**Success Rate: 5/5 (100%)**

## 4. 구조적 일치 (Structural Match)

Design §11.1 파일 구조 대비:

| Design 명세 | 실제 | 상태 |
|-------------|------|------|
| `Sources/AutoLockCore/LockTuning.swift` | 존재 | ✅ |
| `Sources/AutoLockCore/ProximityTypes.swift` | 존재 | ✅ |
| `Sources/AutoLockCore/Devices.swift` | 존재 | ✅ |
| `Sources/AutoLockCore/ProximityEvaluator.swift` | 존재 | ✅ |
| `Tests/AutoLockCoreTests/{ProximityEvaluator,LockTuning}Tests.swift` | 존재 | ✅ |
| `Package.swift` 3 타깃 | executable + library + testTarget | ✅ |
| `Sources/AutoLock/LockTuning.swift` 삭제 | 삭제됨 (git D) | ✅ |

**Structural Match: 100%**

## 5. 기능적 깊이 (Functional Depth)

- `ProximityEvaluator.decide`: 플레이스홀더 없음, 전 분기 실로직 구현 ✅
- 부수효과 격리: `apply(_:)`가 `Action`별로 overlay/lock/wake 수행, 결정 로직과 분리 ✅
- `bestSeen` 갱신, grace 카운트다운, 오버레이 윈도우 모두 보존 ✅

**Functional Depth: 100%**

## 6. 계약 일치 (Contract / Decision Record)

| Decision | 따랐는가 | 비고 |
|----------|----------|------|
| Option B (Clean) 도메인 전면 분리 | ✅ | 도메인 enum/struct 모두 Core로 이전, `public` 부여 |
| 순수 함수 decide (부수효과 컨트롤러 잔류) | ✅ | `ProximityEvaluator`는 Foundation only |
| pruneAfterSeconds = grace*absenceMultiplier + margin | ✅ | margin 2.0s 적용 |
| 타이머 `.common` (CountdownOverlay 패턴 통일) | ✅ | 동일 패턴 |

## 7. 런타임 검증 결과

```
✔ Test run with 12 tests in 2 suites passed after 0.001 seconds.
```

| Suite | 케이스 | 결과 |
|-------|--------|------|
| LockTuningTests | 3 (min/max grace, 도달성 전수증명) | ✅ |
| ProximityEvaluatorTests | 9 (stale/crash/near/weak/unseen/grace만료/overlay×2) | ✅ |

빌드: `swift build` → `Build complete!` (경고는 기존 Keychain deprecation, 본 변경 무관)

## 8. Match Rate

정적 전용 공식(런타임은 단위테스트로 대체, 서버 없음):
```
Overall = Structural×0.2 + Functional×0.4 + Contract×0.4
        = 100×0.2 + 100×0.4 + 100×0.4 = 100%
```
- 단위 테스트 12/12 통과가 Functional/Contract 축을 실증.

**Overall Match Rate: 100%**

## 9. Gap 목록

| 심각도 | 항목 | 상태 |
|--------|------|------|
| — | 없음 | Design 명세 전 항목 구현·검증 완료 |

### 참고(범위 외, Gap 아님)
- `BLEScanner.gracePeriodProvider` 기본값 `{ 60 }`은 sentinel — `ProximityController.init`이 항상 명시 주입하므로 실사용 안 됨(추측성 fallback 아님, Design §4.1 의도).
- prune timer 주기(2초)는 결함 범위 밖이라 미변경 — absence 판정 직후 정리되므로 영향 없음.

## 10. 결론

- **Match Rate 100%**, Critical/Important Gap 0건.
- 90% 임계값 초과 → iterate 불필요, 곧장 `/simplify` 또는 `report` 진행 가능.
