import Foundation

/// Pure classifier for building a Keychain access object whose trusted list is
/// the current signed AutoLock application. Every Security.framework status is
/// explicit so a failed restriction can never fall back to a broader ACL.
///
/// Works in raw `Int32` status codes (Keychain success is `0` / `errSecSuccess`)
/// so the domain layer stays Foundation-only.
public enum KeychainACLPolicy {
    public enum Outcome: Equatable {
        /// The custom no-prompt ACL was built successfully and may be attached.
        case configured
        /// `SecAccessCreate` failed — there is no access object to attach.
        case accessUnavailable
        /// The current signed AutoLock executable could not be represented as
        /// a trusted application, so a least-privilege ACL cannot be built.
        case trustedApplicationUnavailable
        /// Whether the caller should attach the custom `SecAccess`. Only a fully
        /// configured ACL should be attached; every other outcome must abort.
        public var usesCustomAccess: Bool { self == .configured }
    }

    private static let success: Int32 = 0   // errSecSuccess

    /// Classify construction of a `SecAccess` whose trusted list contains only
    /// the current signed AutoLock application. `SecAccessCreate` itself builds
    /// the system-default ACL; rewriting every ACL afterward is unnecessary and
    /// risks changing authorizations unrelated to password reads.
    ///
    /// - Parameters:
    ///   - accessCreateStatus: `SecAccessCreate` OSStatus.
    public static func classify(
        accessCreateStatus: Int32,
        trustedApplicationStatus: Int32 = 0
    ) -> Outcome {
        guard trustedApplicationStatus == success else { return .trustedApplicationUnavailable }
        guard accessCreateStatus == success else { return .accessUnavailable }
        return .configured
    }
}
