import Foundation
import Testing
import AutoLockCore
import AutoLockKit
@testable import AutoLockSystemAdapters

enum CoordinatorFailure: Error, CaseIterable {
    case download
    case stage
    case verify
    case write
    case spawn
}

@MainActor
private final class UpdateTrace {
    var events: [String] = []
}

@MainActor
@Suite struct SelfUpdateCoordinatorTests {
    private let target = URL(fileURLWithPath: "/Applications/AutoLock.app")

    private func release(hasZip: Bool = true) -> ReleaseInfo {
        ReleaseInfo(
            tag: "v0.5.5",
            version: SemanticVersion("0.5.5")!,
            dmgURL: URL(string: "https://example.com/AutoLock.dmg")!,
            dmgFileName: "AutoLock.dmg",
            checksumsURL: URL(string: "https://example.com/SHA256SUMS.txt")!,
            zipURL: hasZip ? URL(string: "https://example.com/AutoLock.zip")! : nil,
            zipFileName: hasZip ? "AutoLock.zip" : nil
        )
    }

    private func makeOperations(
        trace: UpdateTrace,
        failingAt failure: CoordinatorFailure? = nil
    ) -> SelfUpdateOperations {
        let archive = URL(fileURLWithPath: "/tmp/AutoLock.zip")
        let directory = URL(fileURLWithPath: "/tmp/.AutoLockUpdate", isDirectory: true)
        let app = directory.appendingPathComponent("AutoLock.app", isDirectory: true)
        return SelfUpdateOperations(
            downloadArchive: { _, _, _ in
                trace.events.append("download")
                if failure == .download { throw CoordinatorFailure.download }
                return archive
            },
            stageArchive: { _, _, _ in
                trace.events.append("stage")
                if failure == .stage { throw CoordinatorFailure.stage }
                return StagedUpdate(directory: directory, app: app)
            },
            verifyApp: { _, _ in
                trace.events.append("verify")
                if failure == .verify { throw CoordinatorFailure.verify }
            },
            writeHelper: { _, _ in
                trace.events.append("write")
                if failure == .write { throw CoordinatorFailure.write }
                return directory.appendingPathComponent("self-update.sh")
            },
            spawnHelper: { _, _ in
                trace.events.append("spawn")
                if failure == .spawn { throw CoordinatorFailure.spawn }
            },
            cleanup: { url in trace.events.append("cleanup:\(url.lastPathComponent)") },
            terminateApp: { trace.events.append("terminate") }
        )
    }

    @Test func successfulInstallPreservesSecurityOrder() async throws {
        let trace = UpdateTrace()
        let coordinator = SelfUpdateCoordinator(operations: makeOperations(trace: trace))
        try await coordinator.install(release: release(), bundleURL: target, parentPID: 42, dryRun: false)
        #expect(trace.events == [
            "download", "stage", "cleanup:AutoLock.zip", "verify", "write", "spawn", "terminate",
        ])
    }

    @Test func dryRunStopsAfterVerifiedHelperCreation() async throws {
        let trace = UpdateTrace()
        let coordinator = SelfUpdateCoordinator(operations: makeOperations(trace: trace))
        try await coordinator.install(release: release(), bundleURL: target, parentPID: 42, dryRun: true)
        #expect(trace.events == ["download", "stage", "cleanup:AutoLock.zip", "verify", "write"])
    }

    @Test func missingZipFailsBeforeAnySideEffect() async {
        let trace = UpdateTrace()
        let coordinator = SelfUpdateCoordinator(operations: makeOperations(trace: trace))
        await #expect(throws: UpdateError.self) {
            try await coordinator.install(release: release(hasZip: false), bundleURL: target, parentPID: 42, dryRun: false)
        }
        #expect(trace.events.isEmpty)
    }

    @Test(arguments: CoordinatorFailure.allCases)
    func everyFailureStopsAndCleansOwnedArtifacts(_ failure: CoordinatorFailure) async {
        let trace = UpdateTrace()
        let coordinator = SelfUpdateCoordinator(operations: makeOperations(trace: trace, failingAt: failure))
        await #expect(throws: CoordinatorFailure.self) {
            try await coordinator.install(release: release(), bundleURL: target, parentPID: 42, dryRun: false)
        }

        switch failure {
        case .download:
            #expect(trace.events == ["download"])
        case .stage:
            #expect(trace.events == ["download", "stage", "cleanup:AutoLock.zip"])
        case .verify:
            #expect(trace.events == ["download", "stage", "cleanup:AutoLock.zip", "verify", "cleanup:.AutoLockUpdate"])
        case .write:
            #expect(trace.events == ["download", "stage", "cleanup:AutoLock.zip", "verify", "write", "cleanup:.AutoLockUpdate"])
        case .spawn:
            #expect(trace.events == ["download", "stage", "cleanup:AutoLock.zip", "verify", "write", "spawn", "cleanup:.AutoLockUpdate"])
        }
        #expect(!trace.events.contains("terminate"))
    }
}
