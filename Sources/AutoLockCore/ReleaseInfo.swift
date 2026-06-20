import Foundation

/// The subset of a GitHub `releases/latest` payload the updater needs. Pure
/// value type; `parse` decodes raw JSON `Data` with no network access.
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

    /// Decode a `releases/latest` JSON body. Returns nil when the tag isn't a
    /// parseable version or there is no `.dmg` asset (nothing installable).
    public static func parse(_ data: Data) -> ReleaseInfo? {
        struct Payload: Decodable {
            let tag_name: String
            let assets: [Asset]
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let version = SemanticVersion(payload.tag_name) else {
            return nil
        }

        // Prefer the arm64 dmg (this app is Apple Silicon only); fall back to
        // any .dmg if no arch-tagged one is present. Require a dmg to consider
        // the release installable.
        let dmgs = payload.assets.filter { $0.name.hasSuffix(".dmg") }
        guard let dmg = dmgs.first(where: { $0.name.contains("arm64") }) ?? dmgs.first,
              let dmgURL = URL(string: dmg.browser_download_url) else {
            return nil
        }

        // The arm64 zip, if any (same arch-preference as the dmg). Optional —
        // its absence just means the self-updater can't run and we fall back to
        // the dmg manual-install path.
        let zips = payload.assets.filter { $0.name.hasSuffix(".zip") }
        let zip = zips.first(where: { $0.name.contains("arm64") }) ?? zips.first
        let zipURL = zip.flatMap { URL(string: $0.browser_download_url) }

        let checksums = payload.assets
            .first(where: { $0.name == "SHA256SUMS.txt" })
            .flatMap { URL(string: $0.browser_download_url) }

        return ReleaseInfo(
            tag: payload.tag_name,
            version: version,
            dmgURL: dmgURL,
            dmgFileName: dmg.name,
            checksumsURL: checksums,
            zipURL: zipURL,
            zipFileName: zip?.name
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

/// Reads `SHA256SUMS.txt` (`<hex>  <filename>` per line) and compares hashes.
public enum ChecksumVerifier {
    /// The expected lowercase-or-uppercase hex for `fileName`, or nil if absent.
    public static func expectedSHA256(in sums: String, for fileName: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            // shasum format: "<hex>  <filename>" (two spaces, but split on any run).
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            if String(parts[1]) == fileName {
                return String(parts[0])
            }
        }
        return nil
    }

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
    /// entry is a failure, not a pass — every official release ships a complete
    /// `SHA256SUMS.txt` (see release.sh), so a missing line means a broken or
    /// tampered release, which an ad-hoc build (no OS-level publisher trust)
    /// must not install silently.
    public static func verify(sums: String, fileName: String, actual: String) -> Result {
        guard let expected = expectedSHA256(in: sums, for: fileName) else {
            return .entryMissing
        }
        return matches(expected: expected, actual: actual) ? .verified : .mismatch
    }
}
