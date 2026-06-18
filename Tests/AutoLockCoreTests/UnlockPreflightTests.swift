import Testing
import Foundation
@testable import AutoLockCore

/// `UnlockPreflight.decide` is the pure gate extracted from
/// `UnlockTrigger.attempt()`. It checks every *synchronous* precondition —
/// saved password, Accessibility trust, and the ability to vend a
/// `CGEventSource` — before any keystrokes are dispatched, so the caller can
/// report a truthful outcome instead of optimistically returning `.dispatched`
/// and then silently failing inside an async block.
@Suite struct UnlockPreflightTests {

    // 1. No saved password → .noPassword (highest-priority gate).
    @Test func missingPasswordReported() {
        let outcome = UnlockPreflight.decide(
            hasPassword: false,
            hasAccessibility: true,
            canMakeEventSource: true
        )
        #expect(outcome == .noPassword)
    }

    // 2. Password present but Accessibility not granted → .noAccessibility.
    @Test func missingAccessibilityReported() {
        let outcome = UnlockPreflight.decide(
            hasPassword: true,
            hasAccessibility: false,
            canMakeEventSource: true
        )
        #expect(outcome == .noAccessibility)
    }

    // 3. Password + Accessibility but the system won't vend an event source →
    //    .eventSourceUnavailable (the bug: this used to be swallowed).
    @Test func missingEventSourceReported() {
        let outcome = UnlockPreflight.decide(
            hasPassword: true,
            hasAccessibility: true,
            canMakeEventSource: false
        )
        #expect(outcome == .eventSourceUnavailable)
    }

    // 4. All preconditions met → .dispatched (keystrokes may proceed).
    @Test func allReadyDispatches() {
        let outcome = UnlockPreflight.decide(
            hasPassword: true,
            hasAccessibility: true,
            canMakeEventSource: true
        )
        #expect(outcome == .dispatched)
    }

    // 5. Gate precedence: password missing takes priority over every other
    //    failure so the most actionable cause is surfaced first.
    @Test func passwordGateHasPriority() {
        let outcome = UnlockPreflight.decide(
            hasPassword: false,
            hasAccessibility: false,
            canMakeEventSource: false
        )
        #expect(outcome == .noPassword)
    }

    // 6. Accessibility gate takes priority over event-source failure.
    @Test func accessibilityGateBeatsEventSource() {
        let outcome = UnlockPreflight.decide(
            hasPassword: true,
            hasAccessibility: false,
            canMakeEventSource: false
        )
        #expect(outcome == .noAccessibility)
    }
}
