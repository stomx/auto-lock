import Foundation
import AppKit
import CryptoKit
import AutoLockKit
import AutoLockCore

/// System implementations of the update boundaries declared in AutoLockKit,
/// wired in at the composition root. All network / disk / NSWorkspace side
/// effects live here; the decision logic stays in AutoLockCore.

/// GitHub repository the updater queries. Single source so the URL isn't
/// scattered across the client.
private enum UpdateRepo {
    static let owner = "stomx"
    static let name = "auto-lock"
    static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")!
    }
}

/// Fetches `releases/latest` from the GitHub API and parses it.
///
/// `feedURL` defaults to the real GitHub endpoint but is injectable so a
/// staging/fork release — or a local fixture server in `diagnose update` — can
/// be pointed at without code changes.
public struct GitHubUpdateClient: UpdateChecking {
    let feedURL: URL

    public init() {
        self.feedURL = UpdateRepo.latestReleaseAPI
    }

    public init(feedURL: URL) {
        self.feedURL = feedURL
    }

    public func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AutoLock", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.network("HTTP \(code)")
        }
        guard let release = GitHubReleaseParser.parse(data) else {
            throw UpdateError.noRelease
        }
        return release
    }
}

/// Downloads the release DMG to a temp file, verifying it against the
/// published SHA256SUMS.txt when available. Used by the manual-install
/// (DMG-open) fallback path.
public struct DownloadClient: UpdateDownloading {
    public init() {}
    public func download(_ release: ReleaseInfo) async throws -> URL {
        try await UpdateDownload.fetchAndVerify(
            from: release.dmgURL,
            fileName: release.dmgFileName,
            checksumsURL: release.checksumsURL
        )
    }
}

/// Shared "download to a stably-named temp file + fail-closed SHA256 verify"
/// used by both the DMG fallback and the ZIP self-updater.
///
/// FAIL-CLOSED: every official release ships a complete SHA256SUMS.txt
/// (release.sh), and a self-signed build has no Apple-notarized publisher
/// trust, so anything that prevents verification (no checksum asset,
/// download/parse failure, missing entry, or a mismatch) aborts the update
/// rather than installing unverified bits.
enum UpdateDownload {
    static func fetchAndVerify(from url: URL, fileName: String, checksumsURL: URL?) async throws -> URL {
        // 1. Fetch to a stably-named temp file so Finder/ditto see the real name.
        let tmpURL: URL
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: downloaded, to: dest)
            tmpURL = dest
        } catch let e as UpdateError {
            throw e
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }

        // 2. Verify — fail-closed.
        do {
            try await verifyChecksum(of: tmpURL, fileName: fileName, sumsURL: checksumsURL)
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        }
        return tmpURL
    }

    private static func verifyChecksum(of fileURL: URL, fileName: String, sumsURL: URL?) async throws {
        // A release without a checksums asset is itself suspect.
        guard let sumsURL else {
            throw UpdateError.checksumMismatch
        }
        let sums: String
        do {
            let (sumsData, response) = try await URLSession.shared.data(from: sumsURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let text = String(data: sumsData, encoding: .utf8) else {
                throw UpdateError.downloadFailed("체크섬 파일을 받을 수 없습니다")
            }
            sums = text
        } catch let e as UpdateError {
            throw e
        } catch {
            throw UpdateError.downloadFailed("체크섬 파일 다운로드 실패: \(error.localizedDescription)")
        }

        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw UpdateError.downloadFailed("받은 파일을 읽을 수 없습니다")
        }
        let actual = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()

        // Parse the SHA256SUMS text (Kit format adapter), then apply the pure
        // fail-closed policy (Core).
        let expected = Sha256SumsParser.expectedSHA256(in: sums, for: fileName)
        switch ChecksumVerifier.verify(expected: expected, actual: actual) {
        case .verified:
            return
        case .mismatch, .entryMissing:
            throw UpdateError.checksumMismatch
        }
    }
}

/// Opens (mounts) the downloaded DMG via Finder so the user can drag the app to
/// Applications. The manual-install fallback when self-update isn't possible.
@MainActor
public struct SystemDMGOpener: DMGOpening {
    public init() {}
    public func open(_ fileURL: URL) throws {
        guard NSWorkspace.shared.open(fileURL) else {
            throw UpdateError.openFailed(fileURL.lastPathComponent)
        }
    }
}

/// In-place self-updater: downloads the release ZIP, verifies it, unpacks it
/// next to the installed bundle, spawns a detached helper that swaps the bundle
/// after this process exits, then quits. The decision logic (location verdict,
/// helper script text) lives in `AutoLockCore`; this just performs the I/O.
@MainActor
public struct SelfUpdateInstaller: SelfReplacing {
    /// The installed bundle to replace. Injectable so `diagnose` can target a
    /// throwaway path; defaults to the running app.
    let bundleURL: URL
    /// When false (diagnose --dry-run), stop after writing the helper script
    /// and DON'T spawn it or terminate — so the swap can be inspected safely.
    let dryRun: Bool
    private let verifier: StagedAppVerifying

    public init(
        bundleURL: URL = Bundle.main.bundleURL,
        verificationReferenceURL: URL = Bundle.main.bundleURL,
        dryRun: Bool = false,
        verifier: StagedAppVerifying? = nil
    ) {
        self.bundleURL = bundleURL
        self.dryRun = dryRun
        self.verifier = verifier ?? StagedAppVerifier(referenceAppURL: verificationReferenceURL)
    }

    public func canSelfUpdate(_ release: ReleaseInfo) -> Bool {
        guard release.zipURL != nil else { return false }
        return InstallLocation.classify(
            bundlePath: bundleURL.path,
            isWritable: { FileManager.default.isWritableFile(atPath: $0) }
        ) == .replaceable
    }

    public func installAndRelaunch(_ release: ReleaseInfo) async throws {
        let coordinator = SelfUpdateCoordinator(operations: SelfUpdateOperations(
            downloadArchive: { url, name, checksums in
                try await UpdateDownload.fetchAndVerify(from: url, fileName: name, checksumsURL: checksums)
            },
            stageArchive: { archive, release, target in
                try Self.stageArchive(archive, release: release, target: target)
            },
            verifyApp: { app, version in
                try verifier.verify(stagedAppURL: app, expectedVersion: version)
            },
            writeHelper: { plan, directory in
                let script = directory.appendingPathComponent("self-update.sh")
                try SelfUpdateScript.text(for: plan).write(to: script, atomically: true, encoding: .utf8)
                return script
            },
            spawnHelper: { script, arguments in
                try Self.spawnDetached(script.path, arguments)
            },
            cleanup: { try? FileManager.default.removeItem(at: $0) },
            terminateApp: { NSApp.terminate(nil) }
        ))
        try await coordinator.install(
            release: release,
            bundleURL: bundleURL,
            parentPID: ProcessInfo.processInfo.processIdentifier,
            dryRun: dryRun
        )
    }

    private static func stageArchive(_ archive: URL, release: ReleaseInfo, target: URL) throws -> StagedUpdate {
        let directory = target.deletingLastPathComponent()
            .appendingPathComponent(".AutoLockUpdate-\(release.tag)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        let app = directory.appendingPathComponent("AutoLock.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: app.path) else {
            try? FileManager.default.removeItem(at: directory)
            throw UpdateError.unpackFailed("ZIP 안에서 AutoLock.app을 찾지 못했습니다")
        }
        return StagedUpdate(directory: directory, app: app)
    }

    /// Run a tool to completion, throwing on non-zero exit.
    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do {
            try p.run()
        } catch {
            throw UpdateError.unpackFailed(error.localizedDescription)
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdateError.unpackFailed("\(path) exit \(p.terminationStatus)")
        }
    }

    /// Launch `/bin/sh <script> <args…>` so it outlives this process. The child
    /// is reparented to launchd when we exit and keeps running; we point stdio
    /// at a log file for post-mortem debugging and never wait on it.
    private static func spawnDetached(_ scriptPath: String, _ args: [String]) throws {
        let logPath = "/tmp/autolock-update.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let log = FileHandle(forWritingAtPath: logPath) ?? FileHandle.nullDevice

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [scriptPath] + args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = log
        p.standardError = log
        do {
            try p.run()   // do NOT waitUntilExit — it must outlive us
        } catch {
            throw UpdateError.replaceFailed(error.localizedDescription)
        }
    }
}
