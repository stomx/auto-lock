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

    /// 평가에 쓰이는 시계. 일반 동작에서는 `Date()`, 테스트에서는 고정 시각을 주입한다.
    var now: () -> Date = { Date() }

    private var awaySince: Date? = nil
    private var evaluationTimer: Timer? = nil
    private var cancellables: Set<AnyCancellable> = []
    /// True once we've already woken the display for the current locked session.
    /// Reset whenever the screen unlocks so the next lock cycle can wake again.
    private var wakeFiredForCurrentLock: Bool = false

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
                if enabled { self.scanner.startScanning() }
                else       { self.scanner.stopScanning() }
                self.status = enabled ? .watching : .idle
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
            overlay.hide()
            return
        }

        guard !settings.trackedDevices.isEmpty else {
            state = .unknown
            status = .awaitingDevice
            awaySince = nil
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
                NSLog("AutoLock: lock invoked (\(ok ? "ok" : "failed")) reason=\(reason.logDescription)")
                wakeFiredForCurrentLock = false
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
        case .doNothing:
            return
        case .armForNextLock:
            // User unlocked — arm wake for the next lock cycle.
            wakeFiredForCurrentLock = false
        case .attemptUnlock:
            let result = unlocker.attempt()
            NSLog("AutoLock: auto-unlock attempt result=\(result)")
            wakeFiredForCurrentLock = true
        case .wakeDisplay:
            let ok = waker.wake()
            NSLog("AutoLock: proximity wake (\(ok ? "ok" : "failed"))")
            wakeFiredForCurrentLock = true
        }
    }
}
