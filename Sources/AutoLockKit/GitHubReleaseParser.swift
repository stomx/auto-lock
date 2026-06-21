import Foundation
import AutoLockCore

/// Format adapter: decodes a GitHub `releases/latest` JSON body into
/// format-neutral `RemoteReleaseAsset`s, then hands them to the pure domain
/// rule `ReleaseInfo.select` to choose the installable artifacts.
///
/// All GitHub wire-format knowledge (the `tag_name` / `assets` /
/// `browser_download_url` keys) is isolated here, so `AutoLockCore` stays free
/// of any one host's API shape. Pure — operates on `Data`, no network.
public enum GitHubReleaseParser {
    /// Decode a `releases/latest` JSON body into a `ReleaseInfo`. Returns nil
    /// when the JSON is malformed, the tag isn't a parseable version, or there's
    /// no installable `.dmg` asset (the domain rule decides the last two).
    public static func parse(_ data: Data) -> ReleaseInfo? {
        struct Payload: Decodable {
            let tag_name: String
            let assets: [Asset]
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        // Keep every asset (URL optional) so the domain rule selects by name
        // first and only then checks the chosen asset's URL — dropping
        // broken-URL assets here would let `select` silently fall back to a
        // different artifact, changing the fail-closed behavior.
        let assets = payload.assets.map { asset in
            RemoteReleaseAsset(name: asset.name, downloadURL: URL(string: asset.browser_download_url))
        }

        return ReleaseInfo.select(tag: payload.tag_name, assets: assets)
    }
}
