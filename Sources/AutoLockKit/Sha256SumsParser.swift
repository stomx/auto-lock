import Foundation
import AutoLockCore

/// Format adapter for the `SHA256SUMS.txt` text format (`shasum -a 256` output:
/// `<hex>  <filename>` per line). Like `GitHubReleaseParser`, this isolates a
/// concrete wire format in the Kit layer so the pure verification *policy*
/// (`ChecksumVerifier` in `AutoLockCore`) never parses text — it only compares
/// an already-extracted expected hash.
public enum Sha256SumsParser {
    /// The expected hex digest for `fileName` from a `SHA256SUMS.txt` body, or
    /// nil if the file has no line. Lines are `<hex>  <filename>` (two spaces in
    /// shasum output, but we split on any run of spaces/tabs to be lenient).
    public static func expectedSHA256(in sums: String, for fileName: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            if String(parts[1]) == fileName {
                return String(parts[0])
            }
        }
        return nil
    }
}
