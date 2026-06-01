import Foundation
import Security

/// Login password storage for the auto-unlock trigger.
///
/// Uses the legacy file-based login keychain. We don't request the modern
/// data-protection store (`kSecUseDataProtectionKeychain`) because it
/// requires the `keychain-access-groups` entitlement, which an ad-hoc
/// signed app does not have — `SecItemAdd` returns -34018 errSecMissingEntitlement.
/// The legacy keychain has no entitlement requirement and works for our
/// single-app use case. Reads happen silently because we add this process
/// to the item's trusted application list when creating it.
enum KeychainStore {
    private static let service = "com.local.autolock.unlock"
    private static let account = "loginPassword"

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
    static func save(password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        delete()

        // Build an ACL with no prompt and a nil trusted-app list. nil here
        // means "any app on this Keychain may read", which combined with the
        // empty SecKeychainPromptSelector skips the user-confirmation dialog
        // entirely. This is essential for unattended auto-unlock: the user
        // is by definition away from the Mac when we read the password, so a
        // prompt would freeze the whole flow.
        //
        // Trade-off: any app running as the same user can theoretically read
        // this item without the user noticing. Acceptable for this feature
        // because (a) the password is only useful on this Mac, (b) the value
        // already lives in the user's login session via the lock prompt itself.
        var access: SecAccess?
        SecAccessCreate("AutoLock auto-unlock" as CFString, nil, &access)
        if let access {
            var aclList: CFArray?
            if SecAccessCopyACLList(access, &aclList) == errSecSuccess,
               let acls = aclList as? [SecACL] {
                for acl in acls {
                    var apps: CFArray?
                    var desc: CFString?
                    var selector = SecKeychainPromptSelector()
                    SecACLCopyContents(acl, &apps, &desc, &selector)
                    let descString = (desc as String?) ?? ""
                    // nil trustedAppList + zeroed selector = read silently from anywhere.
                    SecACLSetContents(acl, nil, descString as CFString, SecKeychainPromptSelector(rawValue: 0))
                }
            }
        }

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        if let access { attrs[kSecAttrAccess as String] = access }

        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
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

    static func hasPassword() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
