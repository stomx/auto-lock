import Foundation

/// Pure precondition gate for the auto-unlock flow, extracted from
/// `UnlockTrigger.attempt()`.
///
/// `attempt()` used to return `.dispatched` *before* its async keystroke block
/// ran, so a later `CGEventSource` failure inside that block was never
/// surfaced — the caller logged "dispatched" while nothing was typed. By
/// resolving every synchronous precondition up front, the caller can report a
/// truthful outcome and only proceed to keystroke synthesis when `.dispatched`
/// is returned.
public enum UnlockPreflight {
    /// Decide the outcome from the three synchronous preconditions, checked in
    /// priority order so the most actionable failure is surfaced first:
    /// missing password → missing Accessibility → no event source.
    /// `.dispatched` means all gates passed and keystrokes may proceed.
    public static func decide(
        hasPassword: Bool,
        hasAccessibility: Bool,
        canMakeEventSource: Bool
    ) -> UnlockOutcome {
        guard hasPassword else { return .noPassword }
        guard hasAccessibility else { return .noAccessibility }
        guard canMakeEventSource else { return .eventSourceUnavailable }
        return .dispatched
    }
}
