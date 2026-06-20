import Foundation

/// A `major.minor.patch` version, with an optional leading `v`, used to decide
/// whether a GitHub release is newer than the running build. Pure value type —
/// parsing and comparison only, no I/O.
///
/// Pre-release / build-metadata suffixes (`-beta`, `+sha`) are intentionally
/// unsupported: this project tags plain `vX.Y.Z`, and rejecting anything else
/// keeps the comparison unambiguous.
public struct SemanticVersion: Equatable, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse `"1.2.3"` / `"v1.2.3"` / `"1.2"` (patch defaults to 0). Surrounding
    /// whitespace is trimmed. Returns nil for anything that isn't 2–3 numeric
    /// dot-separated components.
    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" {
            s.removeFirst()
        }
        guard !s.isEmpty else { return nil }

        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let nums = parts.map { Int($0) }
        guard nums.allSatisfy({ $0 != nil }) else { return nil }

        self.major = nums[0]!
        self.minor = nums[1]!
        self.patch = parts.count == 3 ? nums[2]! : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
