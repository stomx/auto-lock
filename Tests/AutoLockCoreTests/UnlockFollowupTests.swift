import Testing
import Foundation
@testable import AutoLockCore

/// `UnlockFollowup.decide` is the pure policy for what the controller should do
/// *after* an auto-unlock `attempt()` returns. It closes a regression: the
/// controller previously latched `wakeFiredForCurrentLock = true` unconditionally,
/// so a failed attempt (.noPassword / .noAccessibility / .eventSourceUnavailable)
/// neither woke the display nor allowed a retry this lock cycle — the user was
/// left with a black screen. The policy distinguishes "the password was sent"
/// from "the attempt failed, so at least wake the display as a fallback".
@Suite struct UnlockFollowupTests {

    // 1. Password actually dispatched → no fallback wake, latch fires once.
    @Test func dispatchedLatchesNoFallback() {
        let f = UnlockFollowup.decide(outcome: .dispatched)
        #expect(f.shouldWakeDisplay == false)
        #expect(f.latchFired == true)
    }

    // 2. Reported fully unlocked → no fallback wake, latch fires.
    @Test func unlockedLatchesNoFallback() {
        let f = UnlockFollowup.decide(outcome: .unlocked)
        #expect(f.shouldWakeDisplay == false)
        #expect(f.latchFired == true)
    }

    // 3. No saved password → fall back to waking the display so the user can
    //    authenticate manually, and latch so we don't hammer every tick.
    @Test func noPasswordWakesAsFallback() {
        let f = UnlockFollowup.decide(outcome: .noPassword)
        #expect(f.shouldWakeDisplay == true)
        #expect(f.latchFired == true)
    }

    // 4. No Accessibility → fallback wake.
    @Test func noAccessibilityWakesAsFallback() {
        let f = UnlockFollowup.decide(outcome: .noAccessibility)
        #expect(f.shouldWakeDisplay == true)
        #expect(f.latchFired == true)
    }

    // 5. Event source unavailable → fallback wake.
    @Test func eventSourceUnavailableWakesAsFallback() {
        let f = UnlockFollowup.decide(outcome: .eventSourceUnavailable)
        #expect(f.shouldWakeDisplay == true)
        #expect(f.latchFired == true)
    }
}
