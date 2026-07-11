import Testing
@testable import AutoLockCore

@Suite struct KeychainACLPolicyTests {
    @Test func trustedApplicationAndAccessMustBothSucceed() {
        #expect(KeychainACLPolicy.classify(
            accessCreateStatus: 0,
            trustedApplicationStatus: 0
        ) == .configured)
    }

    @Test func trustedApplicationFailureIsFailClosed() {
        #expect(KeychainACLPolicy.classify(
            accessCreateStatus: 0,
            trustedApplicationStatus: -1
        ) == .trustedApplicationUnavailable)
    }

    @Test func accessCreationFailureIsFailClosed() {
        #expect(KeychainACLPolicy.classify(
            accessCreateStatus: -1,
            trustedApplicationStatus: 0
        ) == .accessUnavailable)
    }

    @Test func onlyConfiguredOutcomeCanAttachCustomAccess() {
        #expect(KeychainACLPolicy.Outcome.configured.usesCustomAccess)
        #expect(!KeychainACLPolicy.Outcome.trustedApplicationUnavailable.usesCustomAccess)
        #expect(!KeychainACLPolicy.Outcome.accessUnavailable.usesCustomAccess)
    }
}
