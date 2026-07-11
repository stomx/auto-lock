import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

// MARK: - 가짜 의존성

actor FakeUpdateChecker: UpdateChecking {
    var result: Result<ReleaseInfo, Error>
    private(set) var callCount = 0
    init(_ result: Result<ReleaseInfo, Error>) { self.result = result }
    func latestRelease() async throws -> ReleaseInfo {
        callCount += 1
        return try result.get()
    }
    func count() -> Int { callCount }
}

/// Checker that suspends until `release()` is called, so a test can hold a
/// `check()` in-flight and fire a second concurrent call deterministically.
actor GatedChecker: UpdateChecking {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    let release: ReleaseInfo
    init(release: ReleaseInfo) { self.release = release }

    func latestRelease() async throws -> ReleaseInfo {
        callCount += 1
        await withCheckedContinuation { c in self.continuation = c }
        return release
    }
    func count() -> Int { callCount }
    func unblock() { continuation?.resume(); continuation = nil }
    func waitUntilEntered() async {
        while callCount == 0 { await Task.yield() }
    }
}

actor FakeDownloader: UpdateDownloading {
    var result: Result<URL, Error>
    private(set) var downloadCount = 0
    init(_ result: Result<URL, Error>) { self.result = result }
    func download(_ release: ReleaseInfo) async throws -> URL {
        downloadCount += 1
        return try result.get()
    }
    func count() -> Int { downloadCount }
}

@MainActor
final class SpyDMGOpener: DMGOpening {
    private(set) var opened: [URL] = []
    var shouldThrow = false
    func open(_ fileURL: URL) throws {
        if shouldThrow { throw UpdateError.openFailed("spy") }
        opened.append(fileURL)
    }
}

@MainActor
final class SpySelfReplacing: SelfReplacing {
    var canUpdate = true
    var shouldThrow = false
    private(set) var installCount = 0
    func canSelfUpdate(_ release: ReleaseInfo) -> Bool { canUpdate }
    func installAndRelaunch(_ release: ReleaseInfo) async throws {
        installCount += 1
        if shouldThrow { throw UpdateError.replaceFailed("spy") }
        // Real impl terminates the app here; the spy just records the call and
        // returns, leaving the controller in .installing.
    }
}

struct StubError: Error {}

// MARK: - 테스트

@MainActor
@Suite struct UpdateControllerTests {

    private func release(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(
            tag: tag,
            version: SemanticVersion(tag)!,
            dmgURL: URL(string: "https://e.com/AutoLock-\(tag.dropFirst())-arm64.dmg")!,
            dmgFileName: "AutoLock-\(tag.dropFirst())-arm64.dmg",
            checksumsURL: URL(string: "https://e.com/SHA256SUMS.txt")!
        )
    }

    /// Release that also carries a zip asset, so self-update is possible.
    private func releaseWithZip(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(
            tag: tag,
            version: SemanticVersion(tag)!,
            dmgURL: URL(string: "https://e.com/AutoLock-\(tag.dropFirst())-arm64.dmg")!,
            dmgFileName: "AutoLock-\(tag.dropFirst())-arm64.dmg",
            checksumsURL: URL(string: "https://e.com/SHA256SUMS.txt")!,
            zipURL: URL(string: "https://e.com/AutoLock-\(tag.dropFirst())-arm64.zip")!,
            zipFileName: "AutoLock-\(tag.dropFirst())-arm64.zip"
        )
    }

    private func makeController(
        current: String = "0.3.1",
        checker: UpdateChecking,
        downloader: UpdateDownloading? = nil,
        opener: SpyDMGOpener? = nil,
        selfUpdater: SelfReplacing? = nil
    ) -> UpdateController {
        UpdateController(
            currentVersion: SemanticVersion(current)!,
            checker: checker,
            downloader: downloader ?? FakeDownloader(.success(URL(fileURLWithPath: "/tmp/a.dmg"))),
            opener: opener ?? SpyDMGOpener(),
            selfUpdater: selfUpdater
        )
    }

    // 1. 초기 상태는 idle.
    @Test func startsIdle() {
        let c = makeController(checker: FakeUpdateChecker(.success(release("v0.3.1"))))
        #expect(c.state == .idle)
    }

    // 2. 더 높은 버전 → available.
    @Test func checkFindsUpdate() async {
        let c = makeController(checker: FakeUpdateChecker(.success(release("v0.3.2"))))
        await c.check()
        #expect(c.state == .available(release("v0.3.2")))
        #expect(c.availableRelease == release("v0.3.2"))
    }

    // 3. 같은 버전 → upToDate.
    @Test func checkUpToDate() async {
        let c = makeController(checker: FakeUpdateChecker(.success(release("v0.3.1"))))
        await c.check()
        #expect(c.state == .upToDate)
        #expect(c.availableRelease == nil)
    }

    // 4. 조회 실패 → failed.
    @Test func checkFailure() async {
        let c = makeController(checker: FakeUpdateChecker(.failure(StubError())))
        await c.check()
        if case .failed = c.state {} else { Issue.record("expected .failed, got \(c.state)") }
    }

    // 5. available에서 다운로드+열기 성공 → opened.
    @Test func downloadAndOpenSucceeds() async {
        let opener = SpyDMGOpener()
        let dl = FakeDownloader(.success(URL(fileURLWithPath: "/tmp/AutoLock.dmg")))
        let c = makeController(checker: FakeUpdateChecker(.success(release("v0.3.2"))), downloader: dl, opener: opener)
        await c.check()
        await c.downloadAndOpen()
        #expect(opener.opened == [URL(fileURLWithPath: "/tmp/AutoLock.dmg")])
        if case .opened = c.state {} else { Issue.record("expected .opened, got \(c.state)") }
    }

    // 6. 다운로드 실패 → failed, 열기 호출 안 됨.
    @Test func downloadFailureDoesNotOpen() async {
        let opener = SpyDMGOpener()
        let dl = FakeDownloader(.failure(StubError()))
        let c = makeController(checker: FakeUpdateChecker(.success(release("v0.3.2"))), downloader: dl, opener: opener)
        await c.check()
        await c.downloadAndOpen()
        #expect(opener.opened.isEmpty)
        if case .failed = c.state {} else { Issue.record("expected .failed, got \(c.state)") }
    }

    // 7. available 아닐 때 downloadAndOpen 호출은 무시(상태 유지).
    @Test func downloadIgnoredWhenNotAvailable() async {
        let dl = FakeDownloader(.success(URL(fileURLWithPath: "/tmp/a.dmg")))
        let c = makeController(checker: FakeUpdateChecker(.success(release("v0.3.1"))), downloader: dl)
        await c.check()                 // upToDate
        await c.downloadAndOpen()       // 무시돼야
        #expect(c.state == .upToDate)
        let n = await (dl as FakeDownloader).count()
        #expect(n == 0)
    }

    // 8. check()가 in-flight인 동안 두 번째 check()는 무시된다(중복 네트워크 호출 방지).
    @Test func concurrentCheckIsIgnored() async {
        let gated = GatedChecker(release: release("v0.3.2"))
        let c = makeController(checker: gated)

        let first = Task { await c.check() }   // continuation에서 멈춤
        await gated.waitUntilEntered()
        #expect(c.state == .checking)

        await c.check()                        // in-flight → 즉시 무시(재진입 X)
        await gated.unblock()
        await first.value

        let n = await gated.count()
        #expect(n == 1)                        // checker는 한 번만 호출
        #expect(c.state == .available(release("v0.3.2")))
    }

    // MARK: self-update 흐름

    // 9. self-updater가 있고 교체 가능하면 downloadAndInstall → installing + 1회 호출.
    @Test func installSucceedsEntersInstalling() async {
        let su = SpySelfReplacing()
        let c = makeController(checker: FakeUpdateChecker(.success(releaseWithZip("v0.3.2"))), selfUpdater: su)
        await c.check()
        await c.downloadAndInstall()
        #expect(su.installCount == 1)
        if case .installing = c.state {} else { Issue.record("expected .installing, got \(c.state)") }
    }

    // 10. 교체 불가 위치(canSelfUpdate=false) → unsupported, 설치 시도 안 함.
    @Test func installUnsupportedWhenCannotReplace() async {
        let su = SpySelfReplacing(); su.canUpdate = false
        let c = makeController(checker: FakeUpdateChecker(.success(releaseWithZip("v0.3.2"))), selfUpdater: su)
        await c.check()
        await c.downloadAndInstall()
        #expect(su.installCount == 0)
        if case .unsupported = c.state {} else { Issue.record("expected .unsupported, got \(c.state)") }
    }

    @Test func unsupportedCanDownloadAndOpenDMGFallback() async {
        let su = SpySelfReplacing(); su.canUpdate = false
        let opener = SpyDMGOpener()
        let dl = FakeDownloader(.success(URL(fileURLWithPath: "/tmp/AutoLock-fallback.dmg")))
        let c = makeController(
            checker: FakeUpdateChecker(.success(releaseWithZip("v0.3.2"))),
            downloader: dl,
            opener: opener,
            selfUpdater: su
        )
        await c.check()
        await c.downloadAndInstall()
        await c.downloadAndOpen()
        #expect(await dl.count() == 1)
        #expect(opener.opened == [URL(fileURLWithPath: "/tmp/AutoLock-fallback.dmg")])
        if case .opened = c.state {} else { Issue.record("expected .opened, got \(c.state)") }
    }

    // 11. self-updater 미주입 → unsupported(폴백 경로).
    @Test func installUnsupportedWhenNoSelfUpdater() async {
        let c = makeController(checker: FakeUpdateChecker(.success(releaseWithZip("v0.3.2"))))
        await c.check()
        await c.downloadAndInstall()
        if case .unsupported = c.state {} else { Issue.record("expected .unsupported, got \(c.state)") }
    }

    // 12. 설치 중 실패 → failed.
    @Test func installFailureReportsFailed() async {
        let su = SpySelfReplacing(); su.shouldThrow = true
        let c = makeController(checker: FakeUpdateChecker(.success(releaseWithZip("v0.3.2"))), selfUpdater: su)
        await c.check()
        await c.downloadAndInstall()
        #expect(su.installCount == 1)
        if case .failed = c.state {} else { Issue.record("expected .failed, got \(c.state)") }
    }

    // 13. available 아닐 때 downloadAndInstall은 무시(설치 시도 안 함).
    @Test func installIgnoredWhenNotAvailable() async {
        let su = SpySelfReplacing()
        let c = makeController(checker: FakeUpdateChecker(.success(release("v0.3.1"))), selfUpdater: su)
        await c.check()                  // upToDate
        await c.downloadAndInstall()     // 무시
        #expect(su.installCount == 0)
        #expect(c.state == .upToDate)
    }
}
