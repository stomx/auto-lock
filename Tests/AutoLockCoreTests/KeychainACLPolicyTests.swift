import Testing
import Foundation
@testable import AutoLockCore

/// `KeychainACLPolicy.classify` is the pure decision extracted from
/// `KeychainStore.save()`. The original code called `SecAccessCreate`,
/// `SecAccessCopyACLList`, and `SecACLSetContents` but ignored every return
/// code, so a failed ACL build silently fell back to a (possibly prompting)
/// default ACL with no signal. This classifier turns the captured OSStatus
/// codes — plus the count of ACLs the no-prompt selector was actually applied
/// to — into an explicit outcome the caller can log and act on.
///
/// `OSStatus`/`errSecSuccess` are Security-framework types; the domain layer
/// stays Foundation-only by working in raw `Int32` status codes (success == 0).
@Suite struct KeychainACLPolicyTests {

    // 1. Create + copy succeed and at least one ACL was rewritten with no
    //    failures → .configured (silent reads guaranteed).
    @Test func allSucceedConfigured() {
        let outcome = KeychainACLPolicy.classify(
            accessCreateStatus: 0,
            copyACLListStatus: 0,
            appliedACLCount: 1,
            setContentsFailed: false
        )
        #expect(outcome == .configured)
    }

    // 2. SecAccessCreate fails → .accessUnavailable (save proceeds with the
    //    default ACL, which may prompt; the caller must not claim silent reads).
    @Test func accessCreateFailureReported() {
        let outcome = KeychainACLPolicy.classify(
            accessCreateStatus: -25240,   // a non-zero failure
            copyACLListStatus: 0,
            appliedACLCount: 1,
            setContentsFailed: false
        )
        #expect(outcome == .accessUnavailable)
    }

    // 3. Access created but reading the ACL list fails → .aclBuildFailed.
    @Test func copyACLListFailureReported() {
        let outcome = KeychainACLPolicy.classify(
            accessCreateStatus: 0,
            copyACLListStatus: -67671,
            appliedACLCount: 0,
            setContentsFailed: false
        )
        #expect(outcome == .aclBuildFailed)
    }

    // 4. Access + list OK but SecACLSetContents failed on some ACL →
    //    .aclBuildFailed (the no-prompt selector may not have stuck).
    @Test func setContentsFailureReported() {
        let outcome = KeychainACLPolicy.classify(
            accessCreateStatus: 0,
            copyACLListStatus: 0,
            appliedACLCount: 1,
            setContentsFailed: true
        )
        #expect(outcome == .aclBuildFailed)
    }

    // 5. accessCreate failure takes priority over downstream ACL failures —
    //    if there's no access object there are no ACLs to fail on.
    @Test func accessCreateFailureHasPriority() {
        let outcome = KeychainACLPolicy.classify(
            accessCreateStatus: -25240,
            copyACLListStatus: -67671,
            appliedACLCount: 0,
            setContentsFailed: true
        )
        #expect(outcome == .accessUnavailable)
    }

    // 6. Only .configured permits attaching the custom access object; the
    //    failure outcomes signal "save with default ACL instead".
    @Test func usesCustomAccessOnlyWhenConfigured() {
        #expect(KeychainACLPolicy.Outcome.configured.usesCustomAccess == true)
        #expect(KeychainACLPolicy.Outcome.accessUnavailable.usesCustomAccess == false)
        #expect(KeychainACLPolicy.Outcome.aclBuildFailed.usesCustomAccess == false)
    }

    // 7. Copy succeeded but the ACL list was empty / failed to cast, so the
    //    no-prompt selector was applied to ZERO ACLs → .aclBuildFailed. This is
    //    the gap codex flagged: an empty list previously slid through as
    //    .configured even though no ACL was actually rewritten.
    @Test func noACLsAppliedIsNotConfigured() {
        let outcome = KeychainACLPolicy.classify(
            accessCreateStatus: 0,
            copyACLListStatus: 0,
            appliedACLCount: 0,
            setContentsFailed: false
        )
        #expect(outcome == .aclBuildFailed)
    }
}
