import Foundation

/// Pure classifier for the result of building a no-prompt Keychain ACL,
/// extracted from `KeychainStore.save()`.
///
/// The original save path called `SecAccessCreate`, `SecAccessCopyACLList`,
/// and `SecACLSetContents` but discarded every `OSStatus`, so a failure to
/// build the silent-read ACL went unnoticed — the item could be written with a
/// default (possibly prompting) ACL while the code assumed silent reads. This
/// classifier turns the captured status codes into an explicit outcome the
/// caller logs and acts on.
///
/// Works in raw `Int32` status codes (Keychain success is `0` / `errSecSuccess`)
/// so the domain layer stays Foundation-only.
public enum KeychainACLPolicy {
    public enum Outcome: Equatable {
        /// The custom no-prompt ACL was built successfully and may be attached.
        case configured
        /// `SecAccessCreate` failed — there is no access object to attach.
        case accessUnavailable
        /// The access object exists but its ACL could not be read or rewritten
        /// to the no-prompt selector.
        case aclBuildFailed

        /// Whether the caller should attach the custom `SecAccess`. Only a fully
        /// configured ACL should be attached; otherwise fall back to the default.
        public var usesCustomAccess: Bool { self == .configured }
    }

    private static let success: Int32 = 0   // errSecSuccess

    /// Classify the ACL build from the captured signals, in priority order:
    /// no access object → can't read the ACL list → the no-prompt selector was
    /// applied to zero ACLs (empty/uncastable list) → a per-ACL
    /// `SecACLSetContents` failure. Only a clean build of at least one ACL
    /// yields `.configured`; anything else means silent reads aren't guaranteed.
    ///
    /// - Parameters:
    ///   - accessCreateStatus: `SecAccessCreate` OSStatus.
    ///   - copyACLListStatus: `SecAccessCopyACLList` OSStatus.
    ///   - appliedACLCount: how many ACLs actually had the no-prompt selector
    ///     written. Zero means the list was empty or failed to cast to
    ///     `[SecACL]`, so nothing was rewritten.
    ///   - setContentsFailed: whether any `SecACLSetContents` call returned
    ///     non-success.
    public static func classify(
        accessCreateStatus: Int32,
        copyACLListStatus: Int32,
        appliedACLCount: Int,
        setContentsFailed: Bool
    ) -> Outcome {
        guard accessCreateStatus == success else { return .accessUnavailable }
        guard copyACLListStatus == success else { return .aclBuildFailed }
        guard appliedACLCount > 0 else { return .aclBuildFailed }
        guard !setContentsFailed else { return .aclBuildFailed }
        return .configured
    }
}
