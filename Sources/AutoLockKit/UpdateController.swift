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
    case noZipAsset                  // self-update needs a .zip; release has none
    case unpackFailed(String)        // ditto -x failed / no .app inside
    case verificationFailed(String)  // staged app identity/signature mismatch
    case replaceFailed(String)       // couldn't spawn the swap helper
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

/// Performs an in-place self-update: download the release ZIP, verify it,
/// unpack it, swap the running app bundle, and relaunch — terminating this
/// process so a detached helper can finish the swap. Implemented in the
/// executable (it touches the filesystem, spawns a process, and calls
/// `NSApp.terminate`).
@MainActor
public protocol SelfReplacing {
    /// Whether the running app can replace itself in place — false when it's
    /// translocated (read-only Gatekeeper copy), the bundle isn't writable, or
    /// the release ships no ZIP. The controller routes to the manual-install
    /// fallback when this is false.
    func canSelfUpdate(_ release: ReleaseInfo) -> Bool
    /// Download + verify + unpack + swap + relaunch. On success it spawns the
    /// detached helper and terminates the app, so it normally does not return.
    /// Throws (without terminating) if any step fails, so the controller can
    /// surface the error.
    func installAndRelaunch(_ release: ReleaseInfo) async throws
}

// MARK: - State

public enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(ReleaseInfo)
    case installing(ReleaseInfo)     // bundle swap + relaunch in progress (app about to quit)
    case unsupported(ReleaseInfo)    // can't self-update here; offer manual install
    case opened(ReleaseInfo)         // DMG mounted; user finishes the drag-install (fallback)
    case failed(String)              // human-readable reason
}

// MARK: - Controller

/// Orchestrates the "check → offer → download → install (or fall back to DMG)"
/// update flow. All the decision logic (version compare, release parse,
/// checksum) lives in pure `AutoLockCore` types; this controller only sequences
/// the injected system boundaries and publishes state for the menu UI.
///
/// The primary path is an in-place self-replace (`downloadAndInstall`): the
/// self-signed build keeps a stable certificate leaf across updates, so the
/// swapped bundle retains its TCC permissions. The mounted-DMG path
/// (`downloadAndOpen`) is the manual fallback used only when the app can't
/// replace itself here — translocated (read-only Gatekeeper copy), the bundle
/// isn't writable, the release ships no ZIP, or no self-updater was wired.
@MainActor
public final class UpdateController: ObservableObject {
    @Published public private(set) var state: UpdateState = .idle

    private let currentVersion: SemanticVersion
    private let checker: UpdateChecking
    private let downloader: UpdateDownloading
    private let opener: DMGOpening
    /// The in-place self-updater. Optional so older wiring (and tests that only
    /// exercise the DMG path) can omit it — when nil, the controller always
    /// uses the manual DMG-open fallback.
    private let selfUpdater: SelfReplacing?
    /// True while a check or download/install is in flight. Guards against
    /// re-entrancy: a second concurrent call would otherwise run a redundant
    /// network request and let a late completion overwrite newer state.
    private var isBusy = false

    public init(
        currentVersion: SemanticVersion,
        checker: UpdateChecking,
        downloader: UpdateDownloading,
        opener: DMGOpening,
        selfUpdater: SelfReplacing? = nil
    ) {
        self.currentVersion = currentVersion
        self.checker = checker
        self.downloader = downloader
        self.opener = opener
        self.selfUpdater = selfUpdater
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
    /// `.available` or `.unsupported` and nothing else is in flight.
    public func downloadAndOpen() async {
        guard !isBusy else { return }
        let release: ReleaseInfo
        switch state {
        case .available(let value), .unsupported(let value): release = value
        default: return
        }
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

    /// Self-update: download the ZIP, verify, swap the bundle in place, and
    /// relaunch. No-op unless we're in `.available` and idle. Routes to the
    /// manual DMG fallback (`.unsupported`) when the app can't replace itself
    /// here (translocated / read-only / no ZIP / no self-updater wired). On
    /// success the app terminates, so this normally doesn't return.
    public func downloadAndInstall() async {
        guard !isBusy, case .available(let release) = state else { return }

        // No self-updater, or this install location can't be replaced → hand
        // off to the manual DMG path so the user still has a way forward.
        guard let selfUpdater, selfUpdater.canSelfUpdate(release) else {
            state = .unsupported(release)
            return
        }

        isBusy = true
        defer { isBusy = false }

        state = .installing(release)
        do {
            // Spawns the detached helper and terminates the app on success.
            try await selfUpdater.installAndRelaunch(release)
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
            case .noZipAsset:            return "릴리스에 자동 업데이트용 ZIP이 없습니다"
            case .unpackFailed(let m):   return "압축 해제 실패: \(m)"
            case .verificationFailed(let m): return "업데이트 검증 실패: \(m)"
            case .replaceFailed(let m):  return "앱 교체 실패: \(m)"
            }
        }
        return (error as NSError).localizedDescription
    }
}
