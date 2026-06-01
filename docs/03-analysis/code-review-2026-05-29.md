# 코드 리뷰 보고서 — 2026-05-29

> 대상: `Sources/AutoLock/*.swift` 전체 (15개 파일, 약 2,100줄)
> 트리거: `/bkit:code-review` (git 작업 트리 clean → 전체 코드베이스 리뷰)
> 필터: 신뢰도 80% 이상 이슈만 보고

## 요약

| 항목 | 값 |
|------|-----|
| 리뷰 파일 | 15 |
| 발견 이슈 | 7 (Critical 1, Major 2, Minor 4) |
| 점수 | 82 / 100 |

전반적으로 품질이 높음. 도메인/프레젠테이션 레이어 분리(`LockReason`·`ControllerStatus` enum이 UI 텍스트를 들고 있지 않음), 튜닝 상수 중앙화(`LockTuning`), "왜"를 설명하는 주석이 인상적. 다만 두 타이머/프루닝 모듈 사이의 **시간 상수 충돌**이 핵심 결함.

---

## 🔴 Critical

### 1. 8초 프루닝이 stale/absence 잠금 분기를 죽은 코드로 만듦

**위치**: `BLEScanner.swift:59` ↔ `ProximityController.swift:136-139`

`BLEScanner.clearStale(olderThan: 8)`이 2초마다 돌며 8초 이상 광고가 없는 디바이스를 `devices`에서 **제거**한다. 그런데 `evaluate()`는 `scanner.devices[tracked.id]`에서 디바이스를 찾아 `lastSeen` 기반 `age`로 판정한다.

```swift
// ProximityController.evaluate()
if age > definitiveAbsenceSeconds {                    // ≥ grace*2 = 최소 30초
    lockNow(reason: .signalStaleSeconds(Int(age)))
} else if age > Double(settings.gracePeriodSeconds) {  // 최소 15초
    handleAway(reason: .signalStaleSeconds(Int(age)))
```

디바이스가 `devices`에 머무는 시간은 **최대 8초**. `gracePeriodSeconds`의 하한이 15초이므로 `age`가 15초·30초를 넘는 일은 **구조적으로 불가능** — 위 두 분기는 절대 실행되지 않는 죽은 코드다. 디바이스가 사라지면 항상 `best == nil` → `handleAway(reason: .deviceUnseen)` 경로로만 빠진다.

- **영향**: "신호 끊김 N초" 즉시 잠금/카운트다운 시나리오가 의도대로 동작하지 않음. 사용자가 멀어져 신호가 끊겨도 `deviceUnseen` 경로의 grace 카운트다운만 거침.
- **제안**: 프루닝 임계값을 `gracePeriodSeconds * absenceMultiplier` 이상으로 연동하거나, prune을 없애고 `evaluate()`가 `lastSeen` age만으로 판정하도록 단일화. "사라짐" 판정 기준을 한 곳(`LockTuning`)으로 모을 것.

---

## 🟠 Major

### 2. `evaluationTimer`가 default RunLoop 모드 → 메뉴 트래킹 중 평가 정지 가능

**위치**: `ProximityController.swift:64`

```swift
evaluationTimer = Timer.scheduledTimer(withTimeInterval: ...) { ... }
```

`scheduledTimer`는 `.default` 모드로 등록된다. `CountdownOverlay`는 같은 문제를 알고 `RunLoop.main.add(timer, forMode: .common)`을 명시했는데(`CountdownOverlay.swift:38-42`), 정작 **핵심 평가 타이머에는 적용되지 않음**. 메뉴 트래킹/드래그 등 UI 이벤트 트래킹 중에는 `.default` 타이머가 멈출 수 있어, 메뉴를 열어둔 채 자리를 비우면 근접 평가가 중단될 수 있다.

- **제안**: `evaluationTimer`도 `Timer(timeInterval:...)` + `RunLoop.main.add(_, forMode: .common)`으로 통일.

### 3. 토글 OFF 시 BLE 스캔이 멈추지 않음

**위치**: `ProximityController.swift:68-74`

```swift
settings.$enabled.sink { enabled in
    if enabled { self.scanner.startScanning() }   // off일 때 stopScanning 없음
    self.status = enabled ? .watching : .idle
}
```

`enabled = false`가 되어도 `status`만 `.idle`로 바뀔 뿐 `scanner.stopScanning()`을 호출하지 않는다. 사용자가 기능을 껐는데도 BLE 스캔(`AllowDuplicates: true` 능동 스캔)이 계속 돌아 배터리를 소모한다.

- **제안**: `else { self.scanner.stopScanning() }` 추가.

---

## 🟡 Minor

### 4. `SecAccessCreate` 반환 상태 미확인

**위치**: `KeychainStore.swift:35`

실패 시 `access`가 nil이라 ACL 설정이 통째로 스킵되지만 로깅이 없어 진단 불가. 평문 비밀번호의 silent-ACL 저장 자체는 주석에 명시된 의도적 trade-off로 확인됨.

### 5. `permissionTimer`가 뷰 생존 동안 항상 동작

**위치**: `MenuView.swift:121,142`

`MenuBarExtra`는 뷰를 상주시키므로 메뉴를 닫아도 1초마다 `AXIsProcessTrustedWithOptions` + `KeychainStore.hasPassword()`(Keychain 조회)가 계속 실행될 수 있음. AX 체크는 저렴하지만 Keychain 조회는 상대적으로 무거움. `.onAppear`/`.onDisappear`로 구독 토글 권장.

### 6. `NSScreen.main` 단발 계산

**위치**: `CountdownOverlay.swift:64`

오버레이 위치/크기를 최초 1회만 산정. 외부 모니터 연결·해상도 변경 시 오버레이가 어긋남. 현재 단일 화면 가정에선 허용 가능.

### 7. `resolved != "Unknown"` 문자열 비교

**위치**: `BLEScanner.swift:97`

실제 기기 이름이 우연히 "Unknown"이면 표시명에서 배제됨. 발생 가능성 낮은 엣지 케이스.

---

## 권고

- **우선순위 1**: 이슈 1·2를 함께 처리. 둘 다 "시간 기반 판정"의 단일 출처가 없어서 생긴 문제. `clearStale` 임계값·`evaluationInterval`·grace·absence를 `LockTuning`에서 일관되게 도출하도록 리팩터링하면 두 결함이 동시에 해소됨.
- 이슈 1은 v0.3.0 plan의 "안전성" 범주와 직결되므로 PDCA 사이클에 편입할 가치가 있음.
