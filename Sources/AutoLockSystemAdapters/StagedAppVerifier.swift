import Foundation
import Security
import AutoLockCore
import AutoLockKit

public struct StagedAppMetadata: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let shortVersion: String?
    public let buildVersion: String?
    public let executableURL: URL?
    public let executableArchitectures: [Int32]

    public init(
        bundleIdentifier: String?,
        shortVersion: String?,
        buildVersion: String?,
        executableURL: URL?,
        executableArchitectures: [Int32]
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.executableURL = executableURL
        self.executableArchitectures = executableArchitectures
    }
}

public enum StagedAppVerificationPolicy {
    public static let expectedBundleIdentifier = "com.local.autolock"
    public static let arm64Architecture: Int32 = 0x0100000C

    public static func validate(
        _ metadata: StagedAppMetadata,
        expectedVersion: SemanticVersion
    ) throws {
        guard metadata.bundleIdentifier == expectedBundleIdentifier else {
            throw UpdateError.verificationFailed("bundle identifier가 AutoLock과 일치하지 않습니다")
        }
        guard let rawVersion = metadata.shortVersion,
              SemanticVersion(rawVersion) == expectedVersion else {
            throw UpdateError.verificationFailed("릴리스 버전과 앱 버전이 일치하지 않습니다")
        }
        guard let build = metadata.buildVersion,
              !build.isEmpty,
              build.allSatisfy(\.isNumber) else {
            throw UpdateError.verificationFailed("유효한 빌드 번호가 없습니다")
        }
        guard metadata.executableURL != nil else {
            throw UpdateError.verificationFailed("앱 실행 파일이 없습니다")
        }
        guard metadata.executableArchitectures.contains(arm64Architecture) else {
            throw UpdateError.verificationFailed("arm64 실행 파일이 아닙니다")
        }
    }
}

public protocol StagedAppVerifying {
    func verify(stagedAppURL: URL, expectedVersion: SemanticVersion) throws
}

public protocol CodeSignatureChecking {
    func validate(stagedAppURL: URL, against referenceAppURL: URL) -> OSStatus
}

public struct StagedAppVerifier: StagedAppVerifying {
    private let referenceAppURL: URL
    private let signatureChecker: CodeSignatureChecking
    private let fileManager: FileManager

    public init(
        referenceAppURL: URL = Bundle.main.bundleURL,
        signatureChecker: CodeSignatureChecking = SystemCodeSignatureChecker(),
        fileManager: FileManager = .default
    ) {
        self.referenceAppURL = referenceAppURL
        self.signatureChecker = signatureChecker
        self.fileManager = fileManager
    }

    public func verify(stagedAppURL: URL, expectedVersion: SemanticVersion) throws {
        guard stagedAppURL.lastPathComponent == "AutoLock.app",
              let bundle = Bundle(url: stagedAppURL) else {
            throw UpdateError.verificationFailed("ZIP의 AutoLock.app 구조가 올바르지 않습니다")
        }
        let executableURL = bundle.executableURL
        let metadata = StagedAppMetadata(
            bundleIdentifier: bundle.bundleIdentifier,
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            executableURL: executableURL,
            executableArchitectures: (bundle.executableArchitectures ?? []).map { $0.int32Value }
        )
        try StagedAppVerificationPolicy.validate(metadata, expectedVersion: expectedVersion)
        guard let executableURL, fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw UpdateError.verificationFailed("앱 실행 파일에 실행 권한이 없습니다")
        }
        let status = signatureChecker.validate(stagedAppURL: stagedAppURL, against: referenceAppURL)
        guard status == errSecSuccess else {
            throw UpdateError.verificationFailed("현재 AutoLock과 코드서명이 일치하지 않습니다 (status \(status))")
        }
    }
}
