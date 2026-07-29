# AutoLock 진단 로깅

AutoLock의 로그는 단순한 문자열 모음이 아니라, 다음 질문을 시간순으로
재구성하기 위한 운영 기록이다.

1. 자동 잠금이 켜져 있었는가?
2. 디바이스가 연동되어 있었고 실제로 감지되었는가?
3. 화면이 열림/잠김 중 어느 상태였는가?
4. 앱이 어떤 동작을 결정하고 macOS에 무엇을 요청했는가?
5. 요청 뒤 실제 화면 상태가 바뀌었는가?
6. 실패했다면 설정, Bluetooth, 시스템 API, 권한, 결과 미확인 중 어디서
   끊겼는가?

## 사용자가 보는 상태

메뉴의 `동작 진단` 카드에 다음 상태가 항상 함께 표시된다.

- `연동됨` / `미연동`
- `화면 열림` / `화면 잠김` / `화면 확인 중`
- `감시 중` / `감시 꺼짐`
- 가장 최근 진단 이벤트와 시각

`진단 DB` 버튼은 영구 SQLite 데이터베이스 위치를 Finder에서 표시한다.

로깅 자체의 기록·영구 저장 경로는 다음 비파괴 명령으로 점검할 수 있다.

```sh
.build/release/AutoLock diagnose logging
```

## 저장 위치와 보존

- SQLite: `~/Library/Application Support/AutoLock/diagnostics.sqlite3`
- 스키마 버전: SQLite `PRAGMA user_version`
- 보존 기간: 최대 90일
- 보존 건수: 최대 25,000개 이벤트
- 저널: WAL, 동기화 수준 `NORMAL`
- DB 권한: 현재 사용자만 읽기/쓰기(`0600`), 상위 디렉터리 `0700`
- macOS Unified Logging subsystem: `com.local.autolock`

DB는 `.app` 번들 밖의 Application Support에 있으므로 앱 업데이트나 동일
사용자의 재설치 후에도 유지된다. 앱 삭제 시에도 자동 삭제하지 않는다.
단위 테스트 프로세스는 사용자 DB에 기록하지 않는다. 암호와 전체 디바이스
식별자는 DB 필드로 전달하지 않는다.

기존 JSONL 로그가 있으면 첫 SQLite 실행 시 트랜잭션으로 이관한다. 이관에
성공한 JSONL만 제거하며, 손상된 파일은 복구를 위해 그대로 둔다.

## 이벤트 구조

`diagnostic_events` 테이블은 아래 필드를 가진다.

| 필드 | 의미 |
|---|---|
| `timestamp` | Unix epoch 초 단위의 실제 시각(`REAL`) |
| `session_id` | 앱 실행 세션 식별자 |
| `category` | lifecycle/settings/bluetooth/proximity/screen/wake/system/ui |
| `level` | info/warning/error |
| `code` | 언어와 무관한 안정적인 이벤트 코드 |
| `outcome` | observed/pending/success/skipped/failure |
| `correlation_id` | 요청과 실제 결과를 연결하는 식별자 |
| `message` | 사용자에게 보여줄 한국어 요약 |
| `metadata_json` | 원인 분석용 비밀정보 없는 JSON 객체 |

잠금과 자동 해제는 API 반환값만으로 성공 처리하지 않는다.

```text
screen_lock_requested (pending, correlation=abc12345)
  -> screen_state_changed (unlocked -> locked)
  -> screen_lock_confirmed (success, correlation=abc12345)
```

5초 동안 실제 화면 상태가 바뀌지 않으면 같은 `correlationID`로
`screen_lock_confirmation_timeout` 또는
`screen_unlock_confirmation_timeout`이 기록된다.

## 핵심 이벤트 코드

| 코드 | 의미 |
|---|---|
| `monitoring_mode_changed` | 자동 잠금 감시 켜짐/꺼짐 |
| `tracked_device_configuration_changed` | 디바이스 연동/해제 |
| `bluetooth_state_changed` | Bluetooth 준비/꺼짐/권한 없음 등 |
| `ble_scan_started`, `ble_scan_stopped` | 실제 CoreBluetooth 스캔 수명 |
| `proximity_state_changed` | 정상 근접/이탈 유예/즉시 잠금 결정 |
| `screen_state_changed` | 설정과 무관하게 관찰한 실제 화면 잠김/열림 |
| `screen_lock_requested` | macOS 잠금 API 호출 직전 |
| `screen_lock_request_failed` | macOS 잠금 API 자체 실패 |
| `screen_lock_confirmed` | 잠금 화면을 실제 확인 |
| `screen_lock_confirmation_timeout` | 잠금 API 성공 후 실제 잠금 미확인 |
| `auto_unlock_attempted` | 자동 해제 사전조건 결과 또는 입력 전송 |
| `screen_unlock_confirmed` | 자동 해제 후 실제 화면 열림 확인 |
| `screen_unlock_confirmation_timeout` | 입력 전송 후에도 화면 잠김 |
| `display_wake_requested` | 근접 복귀 시 화면 깨우기 요청 |
| `main_menu_opened`, `main_menu_closed` | 메인 상태 화면 열림/닫힘 |
| `device_picker_opened`, `device_picker_closed` | 연동 화면 열림/닫힘 |

## 장애 분석 순서

1. 실패 이벤트를 찾는다.

   ```sh
   sqlite3 -readonly \
     "$HOME/Library/Application Support/AutoLock/diagnostics.sqlite3" \
     "SELECT datetime(timestamp, 'unixepoch', 'localtime'), code, message
      FROM diagnostic_events
      WHERE outcome = 'failure'
      ORDER BY timestamp DESC;"
   ```

2. 해당 레코드의 `sessionID`와 `correlationID`로 같은 사건을 묶는다.

   ```sh
   sqlite3 -readonly \
     "$HOME/Library/Application Support/AutoLock/diagnostics.sqlite3" \
     "SELECT timestamp, category, code, outcome, message, metadata_json
      FROM diagnostic_events
      WHERE correlation_id = 'abc12345'
      ORDER BY timestamp;"
   ```

3. 요청 이전의 `monitoring_mode_changed`,
   `tracked_device_configuration_changed`, `bluetooth_state_changed`,
   `proximity_state_changed`를 같은 세션에서 확인한다.
4. 실시간 재현이 필요하면 Unified Logging을 함께 본다.

   ```sh
   log stream \
     --predicate 'subsystem == "com.local.autolock"' \
     --level info
   ```

5. 최근 기록을 한 번에 조회하려면 다음 명령을 쓴다.

   ```sh
   log show --last 30m \
     --predicate 'subsystem == "com.local.autolock"' \
     --info
   ```

## 판정 기준

- `screen_lock_request_failed`: 시스템 잠금 API 호출 단계의 확정 실패다.
- `screen_lock_confirmation_timeout`: 호출은 수락됐지만 실제 잠금은 확인되지
  않았다. 성공으로 간주하지 않는다.
- `auto_unlock_attempted`의 `noPassword`, `noAccessibility`,
  `eventSourceUnavailable`: 자동 해제 사전조건 실패다.
- `screen_unlock_confirmation_timeout`: 키 입력은 예약됐지만 macOS가 화면을
  열지 않았다. 보안 정책에 의한 입력 무시도 이 범주에서 분석한다.
- `screen_state_changed`만 있고 직전 요청의 `correlationID`가 없다면 수동
  잠금/해제 또는 다른 시스템 기능에 의한 상태 변화다.
