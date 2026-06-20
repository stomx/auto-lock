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
struct GitHubUpdateClient: UpdateChecking {
    let feedURL: URL

    init(feedURL: URL = UpdateRepo.latestReleaseAPI) {
        self.feedURL = feedURL
    }

    func latestRelease() async throws -> ReleaseInfo {
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
        guard let release = ReleaseInfo.parse(data) else {
            throw UpdateError.noRelease
        }
        return release
    }
}

/// Downloads the release DMG to a temp file, verifying it against the
/// published SHA256SUMS.txt when available.
struct DownloadClient: UpdateDownloading {
    func download(_ release: ReleaseInfo) async throws -> URL {
        // 1. Fetch the DMG to a temp location.
        let tmpURL: URL
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: release.dmgURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            // Move to a stably-named temp file so Finder shows the real name.
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(release.dmgFileName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: downloaded, to: dest)
            tmpURL = dest
        } catch let e as UpdateError {
            throw e
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }

        // 2. Verify the checksum — FAIL-CLOSED. Every official release ships a
        //    complete SHA256SUMS.txt (release.sh), and an ad-hoc build has no
        //    OS-level publisher trust, so anything that prevents verification
        //    (no checksum asset, download/parse failure, missing entry, or a
        //    mismatch) aborts the update rather than installing unverified bits.
        do {
            try await verifyChecksum(of: tmpURL, fileName: release.dmgFileName, sumsURL: release.checksumsURL)
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        }
        return tmpURL
    }

    private func verifyChecksum(of fileURL: URL, fileName: String, sumsURL: URL?) async throws {
        // An official release without a checksums asset is itself suspect.
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

        switch ChecksumVerifier.verify(sums: sums, fileName: fileName, actual: actual) {
        case .verified:
            return
        case .mismatch, .entryMissing:
            throw UpdateError.checksumMismatch
        }
    }
}

/// Opens (mounts) the downloaded DMG via Finder so the user can drag the app to
/// Applications. We deliberately don't auto-replace the running app.
@MainActor
struct SystemDMGOpener: DMGOpening {
    func open(_ fileURL: URL) throws {
        guard NSWorkspace.shared.open(fileURL) else {
            throw UpdateError.openFailed(fileURL.lastPathComponent)
        }
    }
}
