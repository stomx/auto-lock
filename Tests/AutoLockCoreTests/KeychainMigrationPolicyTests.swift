import Testing
@testable import AutoLockCore

@Suite struct KeychainMigrationPolicyTests {
    @Test func completedMigrationNeverTouchesCredential() {
        #expect(KeychainMigrationPolicy.plan(alreadyMigrated: true, itemState: .present) == .noAction)
    }

    @Test func missingCredentialOnlyMarksMigrationComplete() {
        #expect(KeychainMigrationPolicy.plan(alreadyMigrated: false, itemState: .missing) == .markComplete)
    }

    @Test func legacyCredentialMustBeRemoved() {
        #expect(KeychainMigrationPolicy.plan(alreadyMigrated: false, itemState: .present) == .removeCredential)
    }

    @Test func unknownKeychainStateFailsClosed() {
        #expect(KeychainMigrationPolicy.plan(alreadyMigrated: false, itemState: .unavailable) == .fail)
    }

    @Test(arguments: [(true, KeychainMigrationPolicy.RemovalOutcome.credentialRemoved),
                      (false, KeychainMigrationPolicy.RemovalOutcome.failed)])
    func removalResultIsTruthful(_ succeeded: Bool, _ expected: KeychainMigrationPolicy.RemovalOutcome) {
        #expect(KeychainMigrationPolicy.removalOutcome(deleteSucceeded: succeeded) == expected)
    }
}
