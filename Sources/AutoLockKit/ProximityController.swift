import Foundation
import Combine
import SwiftUI
import AutoLockCore

@MainActor
public final class ProximityController: ObservableObject {
    private let scanner: ProximityScanning
    public let settings: Settings
    private let screenLocker: ScreenLocking
    private let overlay: OverlayPresenting
    private let waker: DisplayWaking
    private let unlocker: UnlockTriggering

    @Published public private(set) var state: ProximityState = .unknown
    @Published public private(set) var bestSeen: (rssi: Double, age: TimeInterval)? = nil
    @Published public private(set) var status: ControllerStatus = .idle
    @Published public private(set) var screenLockState: ScreenLockState = .unknown
    @Published public private(set) var recentEvents: [DiagnosticEvent] = []

    /// 평가에 쓰이는 시계. 일반 동작에서는 단조 클럭(`MonotonicClock`), 테스트에서는
    /// 고정 시각을 주입한다. BLEScanner의 `lastSeen`과 반드시 같은 타임라인이어야
    /// age/deadline 차이가 실제 경과시간과 일치한다(벽시계 점프 내성).
    var now: () -> Date = { MonotonicClock.now() }

    private var awaySince: Date? = nil
    private var evaluationTimer: Timer? = nil
    private var cancellables: Set<AnyCancellable> = []
    /// True once we've already woken the display for the current locked session.
    /// Reset whenever the screen unlocks so the next lock cycle can wake again.
    private var wakeFiredForCurrentLock: Bool = false

    /// 마지막으로 로깅한 깨우기-스킵 사유의 종류. `maybeWakeDisplay()`가 매 틱
    /// (1초) 호출되므로, 같은 사유가 이어질 때 로그가 도배되지 않도록 사유 종류가
    /// 바뀔 때만 한 줄 남기기 위한 dedup 키다.
    private var lastLoggedSkipKind: String? = nil
    private var lastLoggedProximityKey: String? = nil
    private var pendingLock: PendingLockOperation? = nil
    private var pendingUnlock: PendingScreenOperation? = nil
    private var lastEnabledValue: Bool? = nil

    private struct PendingScreenOperation {
        let correlationID: String
        let requestedAt: Date
    }

    private struct PendingLockOperation {
        let correlationID: String
        let reason: LockReason
        let requestedAt: Date
    }

    private static let screenConfirmationTimeout: TimeInterval = 5

    public init(
        scanner: ProximityScanning,
        settings: Settings,
        screenLocker: ScreenLocking,
        overlay: OverlayPresenting,
        waker: DisplayWaking,
        unlocker: UnlockTriggering
    ) {
        self.scanner = scanner
        self.settings = settings
        self.screenLocker = screenLocker
        self.overlay = overlay
        self.waker = waker
        self.unlocker = unlocker

        // Keep BLE pruning in sync with both user-configurable timing values so
        // a silent device survives through tolerance + countdown and can lock.
        scanner.gracePeriodProvider = { [settings] in settings.gracePeriodSeconds }
        scanner.countdownPeriodProvider = { [settings] in settings.countdownSeconds }

        // .common mode so the evaluation keeps firing during UI event tracking
        // (menu open, drag). A plain scheduledTimer registers in .default mode,
        // which pauses under tracking — the same reason CountdownOverlay uses
        // .common for its tick.
        let timer = Timer(timeInterval: LockTuning.evaluationIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer

        settings.$enabled
            .sink { [unowned self] enabled in
                let change = self.lastEnabledValue == nil ? "initial" : "user_change"
                self.lastEnabledValue = enabled
                self.record(
                    .settings,
                    code: "monitoring_mode_changed",
                    outcome: .observed,
                    message: enabled ? "자동 잠금 모니터링 켜짐" : "자동 잠금 모니터링 꺼짐",
                    metadata: ["enabled": String(enabled), "source": change]
                )
                if enabled {
                    self.scanner.startScanning()
                    self.status = .watching
                } else {
                    self.scanner.stopScanning()
                    // Reset published UI state immediately on toggle-off so the
                    // menu doesn't keep showing a stale RSSI / countdown for up
                    // to one evaluation tick. Mirrors evaluate()'s disabled
                    // guard, and clearing awaySince prevents a quick OFF→ON from
                    // resuming a half-finished countdown.
                    self.state = .unknown
                    self.status = .idle
                    self.bestSeen = nil
                    self.awaySince = nil
                    self.overlay.hide()
                }
            }
            .store(in: &cancellables)

        settings.$trackedDevices
            .dropFirst()
            .sink { [weak self] devices in
                self?.record(
                    .settings,
                    code: "tracked_device_configuration_changed",
                    outcome: .observed,
                    message: devices.isEmpty ? "연동 디바이스가 제거됨" : "연동 디바이스가 등록됨",
                    metadata: [
                        "configured": String(!devices.isEmpty),
                        "device_count": String(devices.count)
                    ]
                )
            }
            .store(in: &cancellables)

        record(
            .lifecycle,
            code: "controller_started",
            outcome: .success,
            message: "근접 모니터링 컨트롤러 시작",
            metadata: [
                "enabled": String(settings.enabled),
                "device_count": String(settings.trackedDevices.count),
                "signal_loss_tolerance_seconds": String(settings.gracePeriodSeconds),
                "countdown_seconds": String(settings.countdownSeconds)
            ]
        )
    }

    public var menuBarIcon: String {
        guard settings.enabled else { return "lock.open.fill" }
        switch state {
        case .near: return "lock.open.fill"
        case .borderline: return "lock.rotation"
        case .away: return "lock.fill"
        case .unknown: return "lock.slash"
        }
    }

    public func evaluate() {
        let nowDate = now()
        observeScreenState(at: nowDate)
        if verifyPendingOperations(at: nowDate) {
            refreshRecentEvents()
            return
        }

        guard settings.enabled else {
            state = .unknown
            status = .idle
            awaySince = nil
            bestSeen = nil
            overlay.hide()
            logProximityTransition(key: "disabled", message: "모니터링 비활성 상태", metadata: [:])
            refreshRecentEvents()
            return
        }

        guard !settings.trackedDevices.isEmpty else {
            state = .unknown
            status = .awaitingDevice
            awaySince = nil
            bestSeen = nil
            overlay.hide()
            logProximityTransition(
                key: "unconfigured",
                message: "연동된 디바이스가 없어 감지를 기다리지 않음",
                metadata: ["configured": "false"]
            )
            refreshRecentEvents()
            return
        }

        // Pick the strongest tracked device currently visible to the scanner.
        let best = BestDeviceSelector.select(
            trackedIDs: settings.trackedDevices.map(\.id),
            from: scanner.devices
        )

        if let best {
            bestSeen = (best.smoothedRssi, nowDate.timeIntervalSince(best.lastSeen))
        } else {
            bestSeen = nil
        }

        // All branch logic lives in the pure evaluator; the controller only
        // reflects the published state and performs the requested side effect.
        let decision = ProximityEvaluator.decide(ProximitySnapshot(
            now: nowDate,
            best: best,
            rssiThreshold: settings.rssiThreshold,
            definitiveAwayThreshold: settings.definitiveAwayThreshold,
            gracePeriodSeconds: settings.gracePeriodSeconds,
            countdownSeconds: settings.countdownSeconds,
            awaySince: awaySince
        ))
        apply(decision)
        refreshRecentEvents()
    }

    /// Reflect a pure `ProximityDecision` onto published state and run its side
    /// effect. The decision itself carries no clock or I/O — that all happens here.
    private func apply(_ decision: ProximityDecision) {
        // The away-cycle start as it stood *before* this decision. A failed
        // lock needs it: the countdown-expiry lock branch resets awaySince to nil,
        // and if we kept that on failure the next tick would restart the
        // countdown instead of re-locking. Restoring the prior value keeps the
        // evaluator on the lock path so retries fire every tick.
        let priorAwaySince = awaySince

        state = decision.state
        status = decision.status
        awaySince = decision.awaySince
        logDecisionTransition(decision)

        switch decision.action {
        case .watching:
            overlay.hide()
            maybeWakeDisplay()
        case .showOverlay(let deadline):
            overlay.show(until: deadline)
        case .hideOverlay:
            overlay.hide()
        case .lock(let reason):
            overlay.hide()
            requestLock(reason: reason, priorAwaySince: priorAwaySince)
        }
    }

    /// User-initiated immediate lock goes through the same request/confirmation
    /// pipeline as proximity locking, so it can never be reported as successful
    /// from the API return value alone.
    public func lockNow() {
        let nowDate = now()
        observeScreenState(at: nowDate)
        if screenLockState == .locked {
            record(
                .screen,
                code: "manual_lock_skipped",
                outcome: .skipped,
                message: "이미 잠긴 화면이라 바로 잠금을 생략함"
            )
            return
        }
        requestLock(reason: .userRequested, priorAwaySince: awaySince, origin: "manual")
        refreshRecentEvents()
    }

    private func requestLock(
        reason: LockReason,
        priorAwaySince: Date?,
        origin: String = "proximity"
    ) {
        guard pendingLock == nil else { return }
        guard screenLockState != .locked else {
            status = .locked(reason: reason)
            return
        }

        let correlationID = Self.makeCorrelationID()
        record(
            .screen,
            code: "screen_lock_requested",
            outcome: .pending,
            correlationID: correlationID,
            message: origin == "manual" ? "사용자가 바로 잠금을 요청함" : "근접 상태에 따라 화면 잠금을 요청함",
            metadata: ["origin": origin, "reason": reason.logDescription]
        )

        let ok = screenLocker.lock()
        guard ok else {
            status = .lockFailed(reason: reason)
            awaySince = priorAwaySince
            record(
                .screen,
                level: .error,
                code: "screen_lock_request_failed",
                outcome: .failure,
                correlationID: correlationID,
                message: "macOS 화면 잠금 API가 실패를 반환함",
                metadata: ["origin": origin, "reason": reason.logDescription]
            )
            return
        }

        pendingLock = PendingLockOperation(
            correlationID: correlationID,
            reason: reason,
            requestedAt: now()
        )
        status = .lockRequested(reason: reason)
        wakeFiredForCurrentLock = false
        lastLoggedSkipKind = nil

        // Some implementations (including the test spy) switch synchronously.
        // Confirm immediately when possible; otherwise the next timer tick does.
        observeScreenState(at: now())
        _ = verifyPendingOperations(at: now())
    }

    /// Returns true while a lock request is still waiting for confirmation.
    /// Proximity evaluation pauses in that window to avoid issuing duplicate
    /// lock calls and destroying the original correlation chain.
    private func verifyPendingOperations(at nowDate: Date) -> Bool {
        if let pendingLock {
            if screenLockState == .locked {
                status = .locked(reason: pendingLock.reason)
                record(
                    .screen,
                    code: "screen_lock_confirmed",
                    outcome: .success,
                    correlationID: pendingLock.correlationID,
                    message: "화면 잠금 상태가 실제로 확인됨",
                    metadata: ["state": ScreenLockState.locked.rawValue]
                )
                self.pendingLock = nil
            } else if nowDate.timeIntervalSince(pendingLock.requestedAt) >= Self.screenConfirmationTimeout {
                let reason = pendingLock.reason
                status = .lockFailed(reason: reason)
                awaySince = pendingLock.requestedAt
                record(
                    .screen,
                    level: .error,
                    code: "screen_lock_confirmation_timeout",
                    outcome: .failure,
                    correlationID: pendingLock.correlationID,
                    message: "잠금 요청 후에도 화면 잠금 상태가 확인되지 않음",
                    metadata: [
                        "state": screenLockState.rawValue,
                        "timeout_seconds": String(Int(Self.screenConfirmationTimeout))
                    ]
                )
                self.pendingLock = nil
                return true
            } else {
                status = .lockRequested(reason: pendingLock.reason)
                return true
            }
        }

        if let pendingUnlock {
            if screenLockState == .unlocked {
                record(
                    .screen,
                    code: "screen_unlock_confirmed",
                    outcome: .success,
                    correlationID: pendingUnlock.correlationID,
                    message: "자동 해제 후 화면 열림 상태가 실제로 확인됨",
                    metadata: ["state": ScreenLockState.unlocked.rawValue]
                )
                self.pendingUnlock = nil
            } else if nowDate.timeIntervalSince(pendingUnlock.requestedAt) >= Self.screenConfirmationTimeout {
                record(
                    .screen,
                    level: .error,
                    code: "screen_unlock_confirmation_timeout",
                    outcome: .failure,
                    correlationID: pendingUnlock.correlationID,
                    message: "자동 해제 입력 후에도 화면이 잠긴 상태로 남아 있음",
                    metadata: [
                        "state": screenLockState.rawValue,
                        "timeout_seconds": String(Int(Self.screenConfirmationTimeout))
                    ]
                )
                self.pendingUnlock = nil
            }
        }
        return false
    }

    private func observeScreenState(at timestamp: Date) {
        let observed = screenLocker.screenLockState()
        guard observed != screenLockState else { return }
        let previous = screenLockState
        screenLockState = observed
        let message: String
        let level: DiagnosticLevel
        switch observed {
        case .locked:
            message = "화면 잠김 감지"
            level = .info
        case .unlocked:
            message = "화면 열림 감지"
            level = .info
        case .unknown:
            message = "macOS 화면 잠금 상태를 확인할 수 없음"
            level = .warning
        }
        record(
            .screen,
            level: level,
            code: "screen_state_changed",
            outcome: .observed,
            message: message,
            metadata: [
                "from": previous.rawValue,
                "to": observed.rawValue,
                "monitoring_enabled": String(settings.enabled),
                "device_configured": String(!settings.trackedDevices.isEmpty),
                "observed_at_monotonic": String(format: "%.3f", timestamp.timeIntervalSinceReferenceDate)
            ]
        )
    }

    private func logDecisionTransition(_ decision: ProximityDecision) {
        var metadata: [String: String] = [
            "state": decision.state.rawValue,
            "screen": screenLockState.rawValue,
            "threshold": String(settings.rssiThreshold),
            "signal_loss_tolerance_seconds": String(settings.gracePeriodSeconds),
            "countdown_seconds": String(settings.countdownSeconds)
        ]
        if let bestSeen {
            metadata["rssi"] = String(format: "%.1f", bestSeen.rssi)
            metadata["age_seconds"] = String(format: "%.1f", bestSeen.age)
        }

        switch decision.action {
        case .watching:
            logProximityTransition(key: "watching", message: "연동 디바이스가 정상 범위에서 감지됨", metadata: metadata)
        case .showOverlay, .hideOverlay:
            // These actions are only emitted by the evaluator's away countdown.
            // The concrete cause is still present on subsequent lock events;
            // this transition focuses on the beginning of the configured countdown.
            logProximityTransition(key: "countdown", message: "이탈 가능성을 감지해 잠금 유예를 시작함", metadata: metadata)
        case .lock(let reason):
            metadata["reason"] = reason.logDescription
            let instant: Bool
            if case .instantLock = decision.status { instant = true } else { instant = false }
            logProximityTransition(
                key: "\(instant ? "instant" : "lock"):\(reason.logDescription)",
                message: instant ? "명확한 이탈을 감지해 즉시 잠금을 결정함" : "잠금 유예가 끝나 화면 잠금을 결정함",
                metadata: metadata
            )
        }
    }

    private func logProximityTransition(key: String, message: String, metadata: [String: String]) {
        guard key != lastLoggedProximityKey else { return }
        lastLoggedProximityKey = key
        record(
            .proximity,
            code: "proximity_state_changed",
            outcome: .observed,
            message: message,
            metadata: metadata
        )
    }

    @discardableResult
    private func record(
        _ category: DiagnosticCategory,
        level: DiagnosticLevel = .info,
        code: String,
        outcome: DiagnosticOutcome,
        correlationID: String? = nil,
        message: String,
        metadata: [String: String] = [:]
    ) -> DiagnosticEvent {
        let event = AppLog.record(
            category,
            level: level,
            code: code,
            outcome: outcome,
            correlationID: correlationID,
            message: message,
            metadata: metadata
        )
        refreshRecentEvents()
        return event
    }

    private func refreshRecentEvents() {
        recentEvents = AppLog.recentEvents(limit: 8)
    }

    private static func makeCorrelationID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    /// If the screen is currently locked and the user hasn't been re-detected
    /// yet for this lock session, light up the display so the auth prompt
    /// (Touch ID / password / Apple Watch) is already visible. When the
    /// `autoUnlock` toggle is on we go one step further and post the saved
    /// password to loginwindow. Either way we only fire once per lock session
    /// so we don't hammer the APIs while the user is still nearby.
    private func maybeWakeDisplay() {
        let action = WakeDecision.decide(
            wakeOnProximity: settings.wakeOnProximity,
            autoUnlock: settings.autoUnlock,
            alreadyFired: wakeFiredForCurrentLock,
            isScreenLocked: screenLocker.isScreenLocked(),
            bestRssi: bestSeen?.rssi,
            rssiThreshold: settings.rssiThreshold
        )

        switch action {
        case .doNothing(let reason):
            // 매 틱(1초) 반복되므로 사유 종류가 바뀔 때만 한 줄 남긴다. 이래야
            // "PC 앞에 왔는데 왜 안 풀렸나"를 도배 없이 로그로 추적할 수 있다.
            if lastLoggedSkipKind != reason.kind {
                lastLoggedSkipKind = reason.kind
                AppLog.wake.info("skip auto-wake: \(reason.logDescription, privacy: .public)")
            }
            return
        case .armForNextLock:
            // User unlocked — arm wake for the next lock cycle.
            wakeFiredForCurrentLock = false
        case .attemptUnlock:
            // 발화 경로에 진입하면 dedup 키를 비워, 다음 잠금 세션의 첫 스킵 사유가
            // 다시 기록되게 한다.
            lastLoggedSkipKind = nil
            let result = unlocker.attempt()
            let correlationID = Self.makeCorrelationID()
            let resultText = String(describing: result)
            let outcome: DiagnosticOutcome = result == .dispatched || result == .unlocked ? .pending : .failure
            record(
                .wake,
                level: outcome == .failure ? .error : .info,
                code: "auto_unlock_attempted",
                outcome: outcome,
                correlationID: correlationID,
                message: unlockMessage(for: result),
                metadata: ["result": resultText]
            )
            if result == .dispatched {
                pendingUnlock = PendingScreenOperation(
                    correlationID: correlationID,
                    requestedAt: now()
                )
            } else if result == .unlocked {
                observeScreenState(at: now())
                if screenLockState == .unlocked {
                    record(
                        .screen,
                        code: "screen_unlock_confirmed",
                        outcome: .success,
                        correlationID: correlationID,
                        message: "자동 해제 직후 화면 열림 상태가 확인됨"
                    )
                }
            }
            // If the attempt couldn't run (no password / no Accessibility / no
            // event source), fall back to at least waking the display so the
            // user isn't left with a black screen and no way to authenticate.
            let followup = UnlockFollowup.decide(outcome: result)
            if followup.shouldWakeDisplay {
                let ok = waker.wake()
                record(
                    .wake,
                    level: ok ? .info : .error,
                    code: "fallback_display_wake",
                    outcome: ok ? .success : .failure,
                    correlationID: correlationID,
                    message: ok ? "자동 해제 실패 후 화면 깨우기 요청 성공" : "자동 해제 실패 후 화면 깨우기 요청도 실패"
                )
            }
            wakeFiredForCurrentLock = followup.latchFired
        case .wakeDisplay:
            lastLoggedSkipKind = nil
            let ok = waker.wake()
            record(
                .wake,
                level: ok ? .info : .error,
                code: "display_wake_requested",
                outcome: ok ? .success : .failure,
                message: ok ? "근접 감지로 화면 깨우기 요청 성공" : "근접 감지 화면 깨우기 요청 실패",
                metadata: ["screen": screenLockState.rawValue]
            )
            wakeFiredForCurrentLock = true
        }
    }

    private func unlockMessage(for result: UnlockOutcome) -> String {
        switch result {
        case .unlocked: return "자동 화면 해제가 즉시 완료됨"
        case .dispatched: return "자동 화면 해제 입력을 전송하고 결과 확인 중"
        case .noPassword: return "저장된 로그인 암호가 없어 자동 해제하지 못함"
        case .noAccessibility: return "접근성 권한이 없어 자동 해제하지 못함"
        case .eventSourceUnavailable: return "키 입력 이벤트를 만들 수 없어 자동 해제하지 못함"
        }
    }
}
