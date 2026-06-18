import Foundation
import Security
import AutoLockCore

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
        //
        // ⚠️ DEPRECATION IS INTENTIONAL. The SecAccess*/SecACL* calls below are
        // deprecated (SecKeychain, macOS 10.10) and the compiler will warn on
        // each. We keep them on purpose: the modern data-protection keychain
        // requires the `keychain-access-groups` entitlement, which an ad-hoc
        // signed build does not have, so `SecItemAdd` fails with
        // errSecMissingEntitlement (-34018). There is no first-class Swift way
        // to scope-suppress these warnings without making the surrounding code
        // *look* deprecated, so we leave the warnings visible and document why
        // — the warnings mirror Security.framework's lifecycle, not ours.
        var access: SecAccess?
        let createStatus = SecAccessCreate("AutoLock auto-unlock" as CFString, nil, &access)

        var copyStatus: OSStatus = errSecSuccess
        var appliedACLCount = 0
        var setContentsFailed = false
        if createStatus == errSecSuccess, let access {
            var aclList: CFArray?
            copyStatus = SecAccessCopyACLList(access, &aclList)
            if copyStatus == errSecSuccess, let acls = aclList as? [SecACL] {
                for acl in acls {
                    var apps: CFArray?
                    var desc: CFString?
                    var selector = SecKeychainPromptSelector()
                    // A failed read leaves desc nil; we fall back to an empty
                    // description rather than trusting garbage, and record it.
                    let copyContentsStatus = SecACLCopyContents(acl, &apps, &desc, &selector)
                    if copyContentsStatus != errSecSuccess { setContentsFailed = true }
                    let descString = (desc as String?) ?? ""
                    // nil trustedAppList + zeroed selector = read silently from anywhere.
                    let setStatus = SecACLSetContents(acl, nil, descString as CFString, SecKeychainPromptSelector(rawValue: 0))
                    if setStatus != errSecSuccess { setContentsFailed = true }
                    else { appliedACLCount += 1 }
                }
            }
        }

        // Classify the ACL build instead of silently trusting it. An empty or
        // uncastable ACL list (appliedACLCount == 0) no longer slides through
        // as configured. If the no-prompt ACL couldn't be assembled we must NOT
        // attach a half-built access object — fall back to the default ACL and
        // log loudly, because silent auto-unlock reads are no longer guaranteed.
        let aclOutcome = KeychainACLPolicy.classify(
            accessCreateStatus: createStatus,
            copyACLListStatus: copyStatus,
            appliedACLCount: appliedACLCount,
            setContentsFailed: setContentsFailed
        )
        if aclOutcome != .configured {
            NSLog("AutoLock: keychain ACL build incomplete (\(aclOutcome)) — saving with default ACL; reads may prompt")
        }

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        if aclOutcome.usesCustomAccess, let access {
            attrs[kSecAttrAccess as String] = access
        }

        let addStatus = SecItemAdd(attrs as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("AutoLock: keychain SecItemAdd failed (status \(addStatus))")
        }
        return addStatus == errSecSuccess
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
