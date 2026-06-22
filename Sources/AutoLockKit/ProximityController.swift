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

        // Keep BLE pruning in sync with the user's grace period so a silent
        // device survives long enough for the stale/absence lock branches to fire.
        scanner.gracePeriodProvider = { [settings] in settings.gracePeriodSeconds }

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
            .sink { [weak self] enabled in
                guard let self else { return }
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
        guard settings.enabled else {
            state = .unknown
            status = .idle
            awaySince = nil
            bestSeen = nil
            overlay.hide()
            return
        }

        guard !settings.trackedDevices.isEmpty else {
            state = .unknown
            status = .awaitingDevice
            awaySince = nil
            bestSeen = nil
            overlay.hide()
            return
        }

        // Pick the strongest tracked device currently visible to the scanner.
        let best = BestDeviceSelector.select(
            trackedIDs: settings.trackedDevices.map(\.id),
            from: scanner.devices
        )

        let nowDate = now()
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
            awaySince: awaySince
        ))
        apply(decision)
    }

    /// Reflect a pure `ProximityDecision` onto published state and run its side
    /// effect. The decision itself carries no clock or I/O — that all happens here.
    private func apply(_ decision: ProximityDecision) {
        // The away-cycle start as it stood *before* this decision. A failed
        // lock needs it: the grace-expiry lock branch resets awaySince to nil,
        // and if we kept that on failure the next tick would restart the
        // countdown instead of re-locking. Restoring the prior value keeps the
        // evaluator on the lock path so retries fire every tick.
        let priorAwaySince = awaySince

        state = decision.state
        status = decision.status
        awaySince = decision.awaySince

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
            if !screenLocker.isScreenLocked() {
                let ok = screenLocker.lock()
                AppLog.proximity.info("lock invoked (\(ok ? "ok" : "failed", privacy: .public)) reason=\(reason.logDescription, privacy: .public)")
                if ok {
                    wakeFiredForCurrentLock = false
                    // 새 잠금 세션 시작 — 스킵 사유 dedup 키를 비워 다음 깨우기
                    // 평가의 첫 스킵 사유가 반드시 한 줄 기록되게 한다.
                    lastLoggedSkipKind = nil
                } else {
                    // Don't pretend we locked. Surface the failure and keep the
                    // pre-lock away-cycle start so the next tick retries locking
                    // rather than restarting the countdown.
                    status = .lockFailed(reason: reason)
                    awaySince = priorAwaySince
                }
            }
        }
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
            AppLog.wake.info("auto-unlock attempt result=\(String(describing: result), privacy: .public)")
            // If the attempt couldn't run (no password / no Accessibility / no
            // event source), fall back to at least waking the display so the
            // user isn't left with a black screen and no way to authenticate.
            let followup = UnlockFollowup.decide(outcome: result)
            if followup.shouldWakeDisplay {
                let ok = waker.wake()
                AppLog.wake.info("auto-unlock fallback wake (\(ok ? "ok" : "failed", privacy: .public))")
            }
            wakeFiredForCurrentLock = followup.latchFired
        case .wakeDisplay:
            lastLoggedSkipKind = nil
            let ok = waker.wake()
            AppLog.wake.info("proximity wake (\(ok ? "ok" : "failed", privacy: .public))")
            wakeFiredForCurrentLock = true
        }
    }
}
