import Foundation

/// Pure sequencer for the lock-gated password keystroke loop, extracted from
/// `UnlockTrigger.postString`.
///
/// The auto-unlock flow decides "the screen is locked, type the password" up to
/// `LockTuning.unlockKeystrokeDelaySeconds` *before* the keystrokes are actually
/// posted. During that window the user may authenticate by another means (Touch
/// ID, Apple Watch, or by typing the password themselves). If we kept typing
/// blindly, the saved password would be injected character-by-character into
/// whatever now holds keyboard focus on the *unlocked* desktop — a chat box, a
/// notes window, Spotlight — leaking the plaintext credential to the wrong
/// place.
///
/// This type owns the time-of-use re-checking: it re-probes the lock state
/// before every single character and stops the instant the screen is no longer
/// locked, reporting how far it got so the caller knows whether it's safe to
/// follow up with Return. The actual keystroke synthesis (`CGEvent`) is injected
/// via `emit`, keeping this layer free of system dependencies and unit-testable.
public enum UnlockKeystrokeSequencer {
    public struct TypingResult: Equatable {
        /// How many characters were actually emitted before the loop stopped.
        public let typedCount: Int
        /// True only when every character was emitted while the screen stayed
        /// locked. False means the screen unlocked mid-sequence and the caller
        /// MUST NOT send Return — the remaining input would spill onto the
        /// unlocked desktop.
        public let completed: Bool

        public init(typedCount: Int, completed: Bool) {
            self.typedCount = typedCount
            self.completed = completed
        }
    }

    /// Emit `characterCount` keystrokes one at a time, re-probing
    /// `isScreenLocked` immediately before each so a mid-sequence unlock aborts
    /// the rest. `emit` receives the zero-based index of the character to post;
    /// the caller maps that back to the actual character and its `CGEvent`.
    ///
    /// A negative or zero `characterCount` yields `(0, completed: true)` — there
    /// is nothing to leak, so the caller's empty/edge handling is unchanged.
    public static func runTyping(
        characterCount: Int,
        isScreenLocked: () -> Bool,
        emit: (Int) -> Void
    ) -> TypingResult {
        var typed = 0
        for index in 0..<max(0, characterCount) {
            guard isScreenLocked() else {
                return TypingResult(typedCount: typed, completed: false)
            }
            emit(index)
            typed += 1
        }
        return TypingResult(typedCount: typed, completed: true)
    }
}
