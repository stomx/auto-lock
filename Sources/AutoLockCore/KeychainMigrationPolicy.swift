import Foundation

/// Pure decision table for migrating credentials created by the legacy broad
/// ACL. Security.framework status translation stays in the native adapter.
public enum KeychainMigrationPolicy {
    public enum ItemState: Equatable {
        case missing
        case present
        case unavailable
    }

    public enum Plan: Equatable {
        case noAction
        case markComplete
        case removeCredential
        case fail
    }

    public enum RemovalOutcome: Equatable {
        case credentialRemoved
        case failed
    }

    public static func plan(alreadyMigrated: Bool, itemState: ItemState) -> Plan {
        guard !alreadyMigrated else { return .noAction }
        switch itemState {
        case .missing: return .markComplete
        case .present: return .removeCredential
        case .unavailable: return .fail
        }
    }

    public static func removalOutcome(deleteSucceeded: Bool) -> RemovalOutcome {
        deleteSucceeded ? .credentialRemoved : .failed
    }
}
