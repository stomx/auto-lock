import Foundation
import AutoLockCore
import AutoLockKit

public struct StagedUpdate: Equatable, Sendable {
    public let directory: URL
    public let app: URL

    public init(directory: URL, app: URL) {
        self.directory = directory
        self.app = app
    }
}

@MainActor
public struct SelfUpdateOperations {
    public let downloadArchive: (URL, String, URL?) async throws -> URL
    public let stageArchive: (URL, ReleaseInfo, URL) throws -> StagedUpdate
    public let verifyApp: (URL, SemanticVersion) throws -> Void
    public let writeHelper: (SelfUpdatePlan, URL) throws -> URL
    public let spawnHelper: (URL, [String]) throws -> Void
    public let cleanup: (URL) -> Void
    public let terminateApp: () -> Void

    public init(
        downloadArchive: @escaping (URL, String, URL?) async throws -> URL,
        stageArchive: @escaping (URL, ReleaseInfo, URL) throws -> StagedUpdate,
        verifyApp: @escaping (URL, SemanticVersion) throws -> Void,
        writeHelper: @escaping (SelfUpdatePlan, URL) throws -> URL,
        spawnHelper: @escaping (URL, [String]) throws -> Void,
        cleanup: @escaping (URL) -> Void,
        terminateApp: @escaping () -> Void
    ) {
        self.downloadArchive = downloadArchive
        self.stageArchive = stageArchive
        self.verifyApp = verifyApp
        self.writeHelper = writeHelper
        self.spawnHelper = spawnHelper
        self.cleanup = cleanup
        self.terminateApp = terminateApp
    }
}

/// Deterministic ordering and cleanup rules for self-update preparation. Native
/// network, archive, filesystem and process calls are injected by the adapter.
@MainActor
public struct SelfUpdateCoordinator {
    private let operations: SelfUpdateOperations

    public init(operations: SelfUpdateOperations) {
        self.operations = operations
    }

    public func install(
        release: ReleaseInfo,
        bundleURL: URL,
        parentPID: Int32,
        dryRun: Bool
    ) async throws {
        guard let zipURL = release.zipURL, let zipName = release.zipFileName else {
            throw UpdateError.noZipAsset
        }

        let archive = try await operations.downloadArchive(zipURL, zipName, release.checksumsURL)
        let staged: StagedUpdate
        do {
            staged = try operations.stageArchive(archive, release, bundleURL)
        } catch {
            operations.cleanup(archive)
            throw error
        }
        operations.cleanup(archive)

        do {
            try operations.verifyApp(staged.app, release.version)
        } catch {
            operations.cleanup(staged.directory)
            throw error
        }

        let plan = SelfUpdatePlan(
            parentPID: parentPID,
            stagingAppPath: staged.app.path,
            targetAppPath: bundleURL.path
        )
        let scriptURL: URL
        do {
            scriptURL = try operations.writeHelper(plan, staged.directory)
        } catch {
            operations.cleanup(staged.directory)
            throw error
        }

        if dryRun { return }

        do {
            try operations.spawnHelper(scriptURL, plan.arguments)
        } catch {
            operations.cleanup(staged.directory)
            throw error
        }
        operations.terminateApp()
    }
}
