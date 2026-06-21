import Foundation

/// A downloadable artifact attached to a release, already decoded from whatever
/// wire format the host (GitHub, a staging fork, a local fixture) speaks. The
/// format adapter that produced it — `GitHubReleaseParser` in `AutoLockKit` —
/// owns the JSON-key knowledge; this type is format-neutral so the domain
/// `select` rule below never sees a `tag_name` or `browser_download_url`.
public struct RemoteReleaseAsset: Equatable, Sendable {
    public let name: String          // e.g. "AutoLock-0.3.2-arm64.dmg"
    /// Optional so an asset whose URL the adapter couldn't parse still
    /// participates in name-based selection. `select` chooses by name first,
    /// then checks the URL — so a broken URL on the *chosen* dmg rejects the
    /// whole release (fail-closed) rather than silently falling back to a
    /// different artifact.
    public let downloadURL: URL?

    public init(name: String, downloadURL: URL?) {
        self.name = name
        self.downloadURL = downloadURL
    }
}

/// The subset of a release the updater needs, plus the pure domain rule that
/// chooses which artifacts to install. Value type — `select` operates on
/// already-decoded `RemoteReleaseAsset`s, so no wire-format or network
/// knowledge lives here.
public struct ReleaseInfo: Equatable, Sendable {
    public let tag: String                 // e.g. "v0.3.2"
    public let version: SemanticVersion    // parsed from tag
    public let dmgURL: URL                 // the arm64 .dmg download
    public let dmgFileName: String         // e.g. "AutoLock-0.3.2-arm64.dmg"
    public let checksumsURL: URL?          // SHA256SUMS.txt, if published
    // The arm64 .zip — preferred by the self-updater because it unpacks to a
    // bundle with no mount/detach (unlike the DMG). Optional so a DMG-only
    // release still parses (the v0.4.0 client and the manual-install fallback
    // continue to work off `dmgURL`).
    public let zipURL: URL?                // the arm64 .zip download
    public let zipFileName: String?        // e.g. "AutoLock-0.3.2-arm64.zip"

    public init(
        tag: String,
        version: SemanticVersion,
        dmgURL: URL,
        dmgFileName: String,
        checksumsURL: URL?,
        zipURL: URL? = nil,
        zipFileName: String? = nil
    ) {
        self.tag = tag
        self.version = version
        self.dmgURL = dmgURL
        self.dmgFileName = dmgFileName
        self.checksumsURL = checksumsURL
        self.zipURL = zipURL
        self.zipFileName = zipFileName
    }

    /// Domain rule: given a release tag and its already-decoded assets, choose
    /// the installable artifacts. Returns nil when the tag isn't a parseable
    /// version or there's no `.dmg` asset (nothing installable). Pure — the
    /// caller (a format adapter such as `GitHubReleaseParser`) has already
    /// turned the wire payload into `RemoteReleaseAsset`s, so no JSON-key or
    /// network knowledge lives here.
    public static func select(tag: String, assets: [RemoteReleaseAsset]) -> ReleaseInfo? {
        guard let version = SemanticVersion(tag) else { return nil }

        // Select by NAME first, then read the chosen asset's URL — same order as
        // the original parser, so a broken URL on the chosen dmg rejects the
        // whole release (fail-closed) instead of falling back to another dmg.

        // Prefer the arm64 dmg (this app is Apple Silicon only); fall back to
        // any .dmg if no arch-tagged one is present. A dmg with an unusable URL
        // makes the release non-installable.
        let dmgs = assets.filter { $0.name.hasSuffix(".dmg") }
        guard let dmg = dmgs.first(where: { $0.name.contains("arm64") }) ?? dmgs.first,
              let dmgURL = dmg.downloadURL else {
            return nil
        }

        // The arm64 zip, if any (same arch-preference as the dmg). Optional —
        // its absence (or an unusable URL) just means the self-updater can't run
        // and we fall back to the dmg manual-install path. We only keep the zip
        // when its URL is usable, so `zipURL` and `zipFileName` stay consistent:
        // never a name without a URL (which would look installable but isn't).
        let zips = assets.filter { $0.name.hasSuffix(".zip") }
        let usableZip = (zips.first(where: { $0.name.contains("arm64") }) ?? zips.first)
            .flatMap { z in z.downloadURL.map { (name: z.name, url: $0) } }

        let checksums = assets.first(where: { $0.name == "SHA256SUMS.txt" })

        return ReleaseInfo(
            tag: tag,
            version: version,
            dmgURL: dmgURL,
            dmgFileName: dmg.name,
            checksumsURL: checksums?.downloadURL,
            zipURL: usableZip?.url,
            zipFileName: usableZip?.name
        )
    }
}

/// Decides whether the latest release is worth offering to the user.
public enum UpdateCheck {
    public enum Outcome: Equatable {
        case updateAvailable(ReleaseInfo)
        case upToDate
    }

    /// `.updateAvailable` only when the release is strictly newer than what's
    /// running. A remote that's equal or older (dev build ahead of release) is
    /// treated as up to date — we never prompt a downgrade.
    public static func decide(current: SemanticVersion, latest: ReleaseInfo) -> Outcome {
        latest.version > current ? .updateAvailable(latest) : .upToDate
    }
}

/// Checksum verification *policy* — fail-closed, case-insensitive. Operates on
/// an already-extracted expected hash (`expected == nil` means the file had no
/// entry), so the `SHA256SUMS.txt` *text format* (a shasum wire format) is
/// parsed by an adapter in `AutoLockKit`, not here. Pure domain rule.
public enum ChecksumVerifier {
    /// Case-insensitive hex comparison.
    public static func matches(expected: String, actual: String) -> Bool {
        expected.lowercased() == actual.lowercased()
    }

    public enum Result: Equatable {
        case verified       // entry present and hash matches
        case mismatch       // entry present but hash differs (corrupt/tampered)
        case entryMissing   // no entry for this file in SHA256SUMS — treated as failure
    }

    /// Fail-closed verification: only `.verified` permits proceeding. A missing
    /// entry (`expected == nil`) is a failure, not a pass — every official
    /// release ships a complete `SHA256SUMS.txt` (see release.sh), so a missing
    /// line means a broken or tampered release, which a self-signed build (no
    /// OS-level publisher trust) must not install silently.
    public static func verify(expected: String?, actual: String) -> Result {
        guard let expected else { return .entryMissing }
        return matches(expected: expected, actual: actual) ? .verified : .mismatch
    }
}
