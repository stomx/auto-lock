import Foundation
import Security
import AutoLockCore

/// Login password storage for the auto-unlock trigger.
///
/// Uses the legacy file-based login keychain. We don't request the modern
/// data-protection store (`kSecUseDataProtectionKeychain`) because it
/// requires the `keychain-access-groups` entitlement, which this self-signed
/// app does not have — `SecItemAdd` returns -34018 errSecMissingEntitlement.
/// The legacy keychain has no entitlement requirement and works for our
/// single-app use case. Reads happen silently because we add this process
/// to the item's trusted application list when creating it.
public enum KeychainStore {
    private static let service = "com.local.autolock.unlock"
    private static let account = "loginPassword"
    private static let aclMigrationKey = "keychainRestrictedACLVersion"
    private static let restrictedACLVersion = 1

    public enum MigrationResult: Equatable {
        case notNeeded
        case credentialRemoved
        case failed
    }

    /// The class/service/account triple shared by every query. Each method
    /// layers its own return flags / match limit on top.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    public static func save(password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        // Build an ACL that silently permits only the currently signed AutoLock
        // executable. We pass the list explicitly so this restriction remains
        // visible and reviewable instead of relying on a framework default.
        //
        // ⚠️ DEPRECATION IS INTENTIONAL. The SecAccess* calls below are
        // deprecated (SecKeychain, macOS 10.10) and the compiler will warn on
        // each. We keep them on purpose: the modern data-protection keychain
        // requires the `keychain-access-groups` entitlement, which this
        // signed build does not have, so `SecItemAdd` fails with
        // errSecMissingEntitlement (-34018). There is no first-class Swift way
        // to scope-suppress these warnings without making the surrounding code
        // *look* deprecated, so we leave the warnings visible and document why
        // — the warnings mirror Security.framework's lifecycle, not ours.
        var trustedApplication: SecTrustedApplication?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApplication)
        let trustedApplications: CFArray? = trustedApplication.map { [$0] as CFArray }

        var access: SecAccess?
        let createStatus: OSStatus
        if let trustedApplications {
            createStatus = SecAccessCreate(
                "AutoLock auto-unlock" as CFString,
                trustedApplications,
                &access
            )
        } else {
            createStatus = errSecParam
        }

        // Classify construction instead of falling back to a default ACL. The
        // explicit trusted list is enough: Security.framework documents that
        // listed apps access without confirmation while other apps do not.
        let aclOutcome = KeychainACLPolicy.classify(
            accessCreateStatus: createStatus,
            trustedApplicationStatus: trustedStatus
        )
        guard aclOutcome == .configured, let access else {
            AppLog.system.error("keychain restricted ACL build failed (\(String(describing: aclOutcome), privacy: .public)); password was not changed")
            return false
        }

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccess as String] = access

        // Delete only after the safe replacement ACL is ready. If deletion
        // fails, preserve the old credential instead of creating ambiguity.
        guard delete() else {
            AppLog.system.error("keychain old item deletion failed; password was not changed")
            return false
        }

        let addStatus = SecItemAdd(attrs as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLog.system.error("keychain SecItemAdd failed (status \(addStatus, privacy: .public))")
        } else {
            UserDefaults.standard.set(restrictedACLVersion, forKey: aclMigrationKey)
        }
        return addStatus == errSecSuccess
    }

    public static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return password
    }

    public static func hasPassword() -> Bool {
        passwordItemStatus() == errSecSuccess
    }

    private static func passwordItemStatus() -> OSStatus {
        var query = baseQuery
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil)
    }

    @discardableResult
    public static func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Removes the credential created by releases that used an unrestricted
    /// no-prompt ACL. Copying it into the new ACL would require reading and
    /// rewriting a login password without an explicit user action, so the safe
    /// migration is deletion followed by deliberate re-entry in the UI.
    public static func migrateLegacyUnrestrictedItemIfNeeded(
        defaults: UserDefaults = .standard
    ) -> MigrationResult {
        let alreadyMigrated = defaults.integer(forKey: aclMigrationKey) >= restrictedACLVersion
        if KeychainMigrationPolicy.plan(alreadyMigrated: alreadyMigrated, itemState: .unavailable) == .noAction {
            return .notNeeded
        }
        let status = passwordItemStatus()
        let itemState: KeychainMigrationPolicy.ItemState
        switch status {
        case errSecItemNotFound: itemState = .missing
        case errSecSuccess: itemState = .present
        default: itemState = .unavailable
        }
        let plan = KeychainMigrationPolicy.plan(
            alreadyMigrated: false,
            itemState: itemState
        )
        switch plan {
        case .noAction:
            return .notNeeded
        case .markComplete:
            defaults.set(restrictedACLVersion, forKey: aclMigrationKey)
            return .notNeeded
        case .fail:
            AppLog.system.error("legacy keychain item status could not be determined (status \(status, privacy: .public))")
            return .failed
        case .removeCredential:
            switch KeychainMigrationPolicy.removalOutcome(deleteSucceeded: delete()) {
            case .credentialRemoved:
                defaults.set(restrictedACLVersion, forKey: aclMigrationKey)
                return .credentialRemoved
            case .failed:
                AppLog.system.error("legacy unrestricted keychain item could not be removed")
                return .failed
            }
        }
    }
}
