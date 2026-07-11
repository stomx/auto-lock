import Testing
import Foundation
@testable import AutoLockCore

/// `UnlockKeystrokeSequencer.runTyping` is the pure, lock-gated keystroke loop
/// extracted from `UnlockTrigger.postString`. It exists to close a credential
/// leak: the auto-unlock decision ("screen is locked, type the password") is
/// made up to `unlockKeystrokeDelaySeconds` before the keys are actually posted,
/// so the user may unlock by another means (Touch ID / Apple Watch / manual
/// typing) in between. If the loop kept typing blindly, the plaintext password
/// would spill into whatever app holds focus on the now-unlocked desktop.
///
/// The sequencer re-probes the lock state before every character and stops the
/// instant it's unlocked, reporting how far it got so the caller can suppress
/// the follow-up Return. These tests drive that contract with fake lock probes —
/// no system calls, no `CGEvent`.
@Suite struct UnlockKeystrokeSequencerTests {

    // 1. Screen stays locked the whole time → every character is emitted, in
    //    order, and the result is `completed` so the caller may send Return.
    @Test func staysLockedTypesAllAndCompletes() {
        var emitted: [Int] = []
        let result = UnlockKeystrokeSequencer.runTyping(
            characterCount: 4,
            isScreenLocked: { true },
            emit: { emitted.append($0); return true }
        )
        #expect(emitted == [0, 1, 2, 3])
        #expect(result.typedCount == 4)
        #expect(result.completed == true)
    }

    // 2. THE BUG: the screen unlocks partway through typing. The loop must stop
    //    immediately — no further characters emitted — and report `completed ==
    //    false` so the caller knows NOT to send Return into the unlocked desktop.
    //    Here the probe returns locked for the first 2 checks, then unlocked.
    @Test func unlocksMidTypingStopsAndReportsIncomplete() {
        var probeCount = 0
        var emitted: [Int] = []
        let result = UnlockKeystrokeSequencer.runTyping(
            characterCount: 6,
            isScreenLocked: {
                probeCount += 1
                return probeCount <= 2   // locked for chars 0 and 1, then unlocked
            },
            emit: { emitted.append($0); return true }
        )
        // Only the first two characters made it out; the rest are suppressed.
        #expect(emitted == [0, 1])
        #expect(result.typedCount == 2)
        #expect(result.completed == false)
    }

    // 3. Already unlocked before the first character → nothing is emitted at all
    //    and the result is incomplete. Covers the case where the user unlocked
    //    during the keystroke delay, before the loop even started.
    @Test func alreadyUnlockedEmitsNothing() {
        var emitted: [Int] = []
        let result = UnlockKeystrokeSequencer.runTyping(
            characterCount: 5,
            isScreenLocked: { false },
            emit: { emitted.append($0); return true }
        )
        #expect(emitted.isEmpty)
        #expect(result.typedCount == 0)
        #expect(result.completed == false)
    }

    // 4. The lock state is re-probed BEFORE every character, not just once. A
    //    single up-front check would let the password leak the moment focus
    //    changed mid-typing. We assert one probe per attempted character.
    @Test func reprobesLockStateBeforeEachCharacter() {
        var probeCount = 0
        let result = UnlockKeystrokeSequencer.runTyping(
            characterCount: 3,
            isScreenLocked: { probeCount += 1; return true },
            emit: { _ in true }
        )
        #expect(probeCount == 3)
        #expect(result.completed == true)
    }

    // 5. Empty password → trivially complete with nothing emitted, and the lock
    //    state isn't even probed. Guards the `0..<max(0, count)` edge so an empty
    //    string can't crash or spuriously report incomplete.
    @Test func emptyStringCompletesWithoutProbing() {
        var probeCount = 0
        var emitted: [Int] = []
        let result = UnlockKeystrokeSequencer.runTyping(
            characterCount: 0,
            isScreenLocked: { probeCount += 1; return true },
            emit: { emitted.append($0); return true }
        )
        #expect(emitted.isEmpty)
        #expect(probeCount == 0)
        #expect(result.typedCount == 0)
        #expect(result.completed == true)
    }

    @Test func emissionFailureStopsImmediatelyAndReportsFailure() {
        var emitted: [Int] = []
        let result = UnlockKeystrokeSequencer.runTyping(
            characterCount: 5,
            isScreenLocked: { true },
            emit: { index in
                emitted.append(index)
                return index != 1
            }
        )
        #expect(emitted == [0, 1])
        #expect(result.typedCount == 1)
        #expect(result.stopReason == .emissionFailed)
        #expect(result.completed == false)
    }
}
