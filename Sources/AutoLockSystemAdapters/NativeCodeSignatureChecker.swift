import Foundation
import Security

/// Thin Security.framework bridge. Decision-making remains in
/// `StagedAppVerifier`; this type only translates URLs into SecStaticCode calls.
public struct SystemCodeSignatureChecker: CodeSignatureChecking {
    public init() {}

    public func validate(stagedAppURL: URL, against referenceAppURL: URL) -> OSStatus {
        var referenceCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(referenceAppURL as CFURL, [], &referenceCode)
        guard status == errSecSuccess, let referenceCode else { return status }

        let strictFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        status = SecStaticCodeCheckValidity(referenceCode, strictFlags, nil)
        guard status == errSecSuccess else { return status }

        var requirement: SecRequirement?
        status = SecCodeCopyDesignatedRequirement(referenceCode, [], &requirement)
        guard status == errSecSuccess, let requirement else { return status }

        var stagedCode: SecStaticCode?
        status = SecStaticCodeCreateWithPath(stagedAppURL as CFURL, [], &stagedCode)
        guard status == errSecSuccess, let stagedCode else { return status }

        return SecStaticCodeCheckValidity(stagedCode, strictFlags, requirement)
    }
}
