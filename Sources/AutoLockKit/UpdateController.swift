import Foundation
import Combine
import AutoLockCore

/// Errors surfaced by the update flow. Kept simple — the UI only shows the
/// message and falls back to "manual download" guidance.
public enum UpdateError: Error, Equatable {
    case network(String)
    case noRelease
    case downloadFailed(String)
    case checksumMismatch
    case openFailed(String)
}

// MARK: - Injected system boundaries

/// Fetches the latest release metadata (network). Implemented in the
/// executable by a URLSession-backed GitHub client.
public protocol UpdateChecking: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}

/// Downloads the release DMG (and verifies its checksum if published), returning
/// a local file URL ready to open.
public protocol UpdateDownloading: Sendable {
    func download(_ release: ReleaseInfo) async throws -> URL
}

/// Opens (mounts) the downloaded DMG so the user can drag the app to
/// Applications. MainActor — it touches NSWorkspace / launches a tool.
@MainActor
public protocol DMGOpening {
    func open(_ fileURL: URL) throws
}

// MARK: - State

public enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(ReleaseInfo)
    case opened(ReleaseInfo)         // DMG mounted; user finishes the drag-install
    case failed(String)              // human-readable reason
}

// MARK: - Controller

/// Orchestrates the "check → offer → download → open DMG" update flow. All the
/// decision logic (version compare, release parse, checksum) lives in pure
/// `AutoLockCore` types; this controller only sequences the injected system
/// boundaries and publishes state for the menu UI.
///
/// Deliberately stops at *opening* the DMG rather than replacing the running
/// app: the ad-hoc-signed build can't self-replace without re-triggering
/// Gatekeeper, so handing the user a mounted DMG is the honest, frictionless
/// endpoint. See README for why full Sparkle-style auto-install isn't used.
@MainActor
public final class UpdateController: ObservableObject {
    @Published public private(set) var state: UpdateState = .idle

    private let currentVersion: SemanticVersion
    private let checker: UpdateChecking
    private let downloader: UpdateDownloading
    private let opener: DMGOpening
    /// True while a check or download/open is in flight. Guards against
    /// re-entrancy: a second concurrent call would otherwise run a redundant
    /// network request and let a late completion overwrite newer state.
    private var isBusy = false

    public init(
        currentVersion: SemanticVersion,
        checker: UpdateChecking,
        downloader: UpdateDownloading,
        opener: DMGOpening
    ) {
        self.currentVersion = currentVersion
        self.checker = checker
        self.downloader = downloader
        self.opener = opener
    }

    /// Convenience: the release the user can update to, if any.
    public var availableRelease: ReleaseInfo? {
        if case .available(let r) = state { return r }
        return nil
    }

    /// Query the latest release and classify it against the running version.
    /// Ignored if a check or download is already running.
    public func check() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        state = .checking
        do {
            let latest = try await checker.latestRelease()
            switch UpdateCheck.decide(current: currentVersion, latest: latest) {
            case .updateAvailable(let r): state = .available(r)
            case .upToDate:               state = .upToDate
            }
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// Download the available release's DMG and open it. No-op unless we're in
    /// `.available` (so a stray tap can't kick off a download) and nothing else
    /// is in flight.
    public func downloadAndOpen() async {
        guard !isBusy, case .available(let release) = state else { return }
        isBusy = true
        defer { isBusy = false }

        state = .downloading(release)
        do {
            let fileURL = try await downloader.download(release)
            try opener.open(fileURL)
            state = .opened(release)
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? UpdateError {
            switch e {
            case .network(let m):        return "네트워크 오류: \(m)"
            case .noRelease:             return "릴리스를 찾을 수 없습니다"
            case .downloadFailed(let m): return "다운로드 실패: \(m)"
            case .checksumMismatch:      return "체크섬 불일치 — 손상된 다운로드"
            case .openFailed(let m):     return "DMG 열기 실패: \(m)"
            }
        }
        return (error as NSError).localizedDescription
    }
}
