import Testing
import Foundation
@testable import AutoLockCore

@Suite struct ProximityEvaluatorTests {

    // Fixed reference clock so tests are deterministic (no wall-clock reads).
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let deviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// Build a snapshot with a visible device whose lastSeen is `age` seconds ago.
    private func snapshot(age: TimeInterval,
                          rssi: Double,
                          threshold: Int = -70,
                          definitiveAway: Int = -80,
                          grace: Int = 15,
                          awaySince: Date? = nil) -> ProximitySnapshot {
        ProximitySnapshot(
            now: now,
            best: .init(id: deviceID, smoothedRssi: rssi, lastSeen: now.addingTimeInterval(-age)),
            rssiThreshold: threshold,
            definitiveAwayThreshold: definitiveAway,
            gracePeriodSeconds: grace,
            awaySince: awaySince
        )
    }

    // #3: age past absence (15*2=30) → instant stale lock
    @Test func staleInstantLock() {
        let d = ProximityEvaluator.decide(snapshot(age: 31, rssi: -50))
        #expect(d.state == .away)
        #expect(d.action == .lock(reason: .signalStaleSeconds(31)))
        #expect(d.status == .instantLock(reason: .signalStaleSeconds(31)))
        #expect(d.awaySince == nil)
    }

    // #4: age past grace (15) but before absence (30) → away countdown, stale reason
    @Test func staleCountdown() {
        let d = ProximityEvaluator.decide(snapshot(age: 20, rssi: -50))
        #expect(d.state == .borderline)
        #expect(d.status == .countdown(reason: .signalStaleSeconds(20), secondsLeft: 15))
        #expect(d.awaySince == now)   // awaySince was nil → starts now
    }

    // #5: RSSI crashed below definitiveAway → instant crash lock
    @Test func signalCrashedInstantLock() {
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -95, definitiveAway: -90))
        #expect(d.action == .lock(reason: .signalCrashed))
        #expect(d.status == .instantLock(reason: .signalCrashed))
    }

    // #6: strong RSSI within range → near/watching
    @Test func nearWatching() {
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -50, threshold: -70))
        #expect(d.state == .near)
        #expect(d.status == .watching)
        #expect(d.action == .watching)
        #expect(d.awaySince == nil)
    }

    // #7: RSSI between thresholds → weak signal away countdown
    @Test func signalWeakCountdown() {
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -75, threshold: -70, definitiveAway: -80))
        #expect(d.state == .borderline)
        #expect(d.status == .countdown(reason: .signalWeak, secondsLeft: 15))
    }

    // #8: no device visible → deviceUnseen away countdown
    @Test func deviceUnseen() {
        let s = ProximitySnapshot(now: now, best: nil, rssiThreshold: -70,
                                  definitiveAwayThreshold: -80, gracePeriodSeconds: 15, awaySince: nil)
        let d = ProximityEvaluator.decide(s)
        #expect(d.state == .borderline)
        #expect(d.status == .countdown(reason: .deviceUnseen, secondsLeft: 15))
        #expect(d.awaySince == now)
    }

    // #9: away started long enough ago that grace has expired → lock
    @Test func graceExpiredLocks() {
        // awaySince 20s ago, grace 15 → remaining = -5 → lock
        let started = now.addingTimeInterval(-20)
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -75, threshold: -70, awaySince: started))
        #expect(d.state == .away)
        #expect(d.action == .lock(reason: .signalWeak))
        #expect(d.status == .locked(reason: .signalWeak))
        #expect(d.awaySince == nil)
    }

    // #10: away within the final overlay window (≤5s) → showOverlay
    @Test func overlayWindowShows() {
        // awaySince 12s ago, grace 15 → remaining = 3 (≤5) → showOverlay until deadline
        let started = now.addingTimeInterval(-12)
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -75, threshold: -70, awaySince: started))
        #expect(d.state == .borderline)
        #expect(d.action == .showOverlay(until: started.addingTimeInterval(15)))
    }

    // away outside the overlay window (>5s remaining) → hideOverlay
    @Test func countdownOutsideOverlayWindowHides() {
        // awaySince 3s ago, grace 15 → remaining = 12 (>5) → hideOverlay
        let started = now.addingTimeInterval(-3)
        let d = ProximityEvaluator.decide(snapshot(age: 1, rssi: -75, threshold: -70, awaySince: started))
        #expect(d.action == .hideOverlay)
    }
}
