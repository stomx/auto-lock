import Foundation

/// Pure policy for what the controller does *after* an auto-unlock attempt
/// returns its `UnlockOutcome`.
///
/// Fixes a regression in `ProximityController.maybeWakeDisplay()`: the
/// `.attemptUnlock` path latched `wakeFiredForCurrentLock = true`
/// unconditionally, so when `attempt()` failed (`.noPassword`,
/// `.noAccessibility`, `.eventSourceUnavailable`) the controller neither woke
/// the display nor allowed a retry this lock cycle — leaving the user staring
/// at a black screen with no way forward until the next lock.
///
/// The policy splits the two concerns: whether to wake the display as a
/// fallback, and whether to latch (fire once per lock session).
public enum UnlockFollowup {
    public struct Plan: Equatable {
        /// Wake the display so the user can authenticate manually. True only
        /// when the unlock attempt failed and nothing was sent to loginwindow.
        public let shouldWakeDisplay: Bool
        /// Mark the wake/unlock as fired for this lock session. Always true:
        /// success needs no repeat, and failure shouldn't hammer the APIs every
        /// tick while the user is still nearby. (Re-armed on the next unlock.)
        public let latchFired: Bool

        public init(shouldWakeDisplay: Bool, latchFired: Bool) {
            self.shouldWakeDisplay = shouldWakeDisplay
            self.latchFired = latchFired
        }
    }

    public static func decide(outcome: UnlockOutcome) -> Plan {
        switch outcome {
        case .dispatched, .unlocked:
            // Keystrokes were sent (or the screen is already open) — no fallback.
            return Plan(shouldWakeDisplay: false, latchFired: true)
        case .noPassword, .noAccessibility, .eventSourceUnavailable:
            // The attempt couldn't run; at least light up the screen so the
            // user can use Touch ID / password / Apple Watch.
            return Plan(shouldWakeDisplay: true, latchFired: true)
        }
    }
}
