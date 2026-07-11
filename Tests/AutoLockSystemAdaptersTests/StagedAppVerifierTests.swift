import Foundation
import Testing
import AutoLockCore
import AutoLockKit
@testable import AutoLockSystemAdapters

@Suite struct StagedAppVerifierTests {
    private let version = SemanticVersion("0.5.4")!

    private func validMetadata() -> StagedAppMetadata {
        StagedAppMetadata(
            bundleIdentifier: "com.local.autolock",
            shortVersion: "0.5.4",
            buildVersion: "11",
            executableURL: URL(fileURLWithPath: "/tmp/AutoLock"),
            executableArchitectures: [StagedAppVerificationPolicy.arm64Architecture]
        )
    }

    private func makeApp(executable: Bool = true) throws -> (root: URL, app: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = root.appendingPathComponent("AutoLock.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let binary = macOS.appendingPathComponent("AutoLock")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: binary)
        if !executable {
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: binary.path)
        }
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.local.autolock",
            "CFBundleExecutable": "AutoLock",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.5.4",
            "CFBundleVersion": "11",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return (root, app)
    }

    @Test func exactMetadataPasses() throws {
        try StagedAppVerificationPolicy.validate(validMetadata(), expectedVersion: version)
    }

    @Test(arguments: [
        StagedAppMetadata(bundleIdentifier: "evil.app", shortVersion: "0.5.4", buildVersion: "11", executableURL: URL(fileURLWithPath: "/tmp/a"), executableArchitectures: [StagedAppVerificationPolicy.arm64Architecture]),
        StagedAppMetadata(bundleIdentifier: "com.local.autolock", shortVersion: "0.5.3", buildVersion: "11", executableURL: URL(fileURLWithPath: "/tmp/a"), executableArchitectures: [StagedAppVerificationPolicy.arm64Architecture]),
        StagedAppMetadata(bundleIdentifier: "com.local.autolock", shortVersion: "0.5.4", buildVersion: "", executableURL: URL(fileURLWithPath: "/tmp/a"), executableArchitectures: [StagedAppVerificationPolicy.arm64Architecture]),
        StagedAppMetadata(bundleIdentifier: "com.local.autolock", shortVersion: "0.5.4", buildVersion: "11", executableURL: nil, executableArchitectures: [StagedAppVerificationPolicy.arm64Architecture]),
        StagedAppMetadata(bundleIdentifier: "com.local.autolock", shortVersion: "0.5.4", buildVersion: "11", executableURL: URL(fileURLWithPath: "/tmp/a"), executableArchitectures: [7]),
    ])
    func rejectsAnyIdentityMismatch(_ metadata: StagedAppMetadata) {
        #expect(throws: UpdateError.self) {
            try StagedAppVerificationPolicy.validate(metadata, expectedVersion: version)
        }
    }

    @Test func verifiesARealTemporaryAppBundleThroughInjectedSignatureBoundary() throws {
        let (root, app) = try makeApp()
        defer { try? FileManager.default.removeItem(at: root) }

        let verifier = StagedAppVerifier(
            referenceAppURL: app,
            signatureChecker: AcceptingSignatureChecker()
        )
        try verifier.verify(stagedAppURL: app, expectedVersion: version)
    }

    @Test func rejectsWrongBundleStructureBeforeSignatureCheck() {
        let verifier = StagedAppVerifier(signatureChecker: AcceptingSignatureChecker())
        #expect(throws: UpdateError.self) {
            try verifier.verify(
                stagedAppURL: URL(fileURLWithPath: "/tmp/NotAutoLock.app"),
                expectedVersion: version
            )
        }
    }

    @Test func rejectsNonExecutableBundle() throws {
        let (root, app) = try makeApp(executable: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let verifier = StagedAppVerifier(referenceAppURL: app, signatureChecker: AcceptingSignatureChecker())
        #expect(throws: UpdateError.self) {
            try verifier.verify(stagedAppURL: app, expectedVersion: version)
        }
    }

    @Test func rejectsExecutableWithoutArm64MachO() throws {
        let (root, app) = try makeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = app.appendingPathComponent("Contents/MacOS/AutoLock")
        try "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let verifier = StagedAppVerifier(referenceAppURL: app, signatureChecker: AcceptingSignatureChecker())
        #expect(throws: UpdateError.self) {
            try verifier.verify(stagedAppURL: app, expectedVersion: version)
        }
    }

    @Test func rejectsSignatureMismatch() throws {
        let (root, app) = try makeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let verifier = StagedAppVerifier(referenceAppURL: app, signatureChecker: RejectingSignatureChecker())
        #expect(throws: UpdateError.self) {
            try verifier.verify(stagedAppURL: app, expectedVersion: version)
        }
    }
}

private struct AcceptingSignatureChecker: CodeSignatureChecking {
    func validate(stagedAppURL: URL, against referenceAppURL: URL) -> OSStatus { errSecSuccess }
}

private struct RejectingSignatureChecker: CodeSignatureChecking {
    func validate(stagedAppURL: URL, against referenceAppURL: URL) -> OSStatus { errSecAuthFailed }
}
