import Foundation

/// The data describing an in-place bundle swap: which process to wait for, what
/// to copy, and where. Pure value type — it carries no knowledge of *how* the
/// swap is performed (that's a `/bin/sh` script generated in `AutoLockKit`).
///
/// Why the swap runs detached: the running app can't overwrite its own bundle
/// while it's mapped in, so a helper waits for *this* process to exit, replaces
/// the bundle, strips quarantine, and relaunches. This type only describes the
/// plan; the executable builds the helper and spawns it.
///
/// Path safety: the three paths reach `/bin/sh` as positional arguments
/// (`arguments`, passed via `Process.arguments`), never interpolated into the
/// script text — so no shell-quoting is needed and metacharacters in a path
/// can't break out. The helper reads them back as quoted `"$1".."$3"`.
public struct SelfUpdatePlan: Equatable, Sendable {
    /// PID of the running app; the helper waits for it to exit before swapping.
    public let parentPID: Int32
    /// The freshly-unpacked `.app` in a staging dir (same volume as target).
    public let stagingAppPath: String
    /// The installed `.app` to be replaced in place.
    public let targetAppPath: String

    public init(parentPID: Int32, stagingAppPath: String, targetAppPath: String) {
        self.parentPID = parentPID
        self.stagingAppPath = stagingAppPath
        self.targetAppPath = targetAppPath
    }

    /// The positional argument vector the helper reads as `$1..$3`, in that
    /// order. The executable passes these verbatim to `/bin/sh <script> <args…>`
    /// — `SelfUpdateScript.text` documents the same `$1=pid $2=staging $3=target`
    /// contract, and `SelfUpdateScriptTests` pins the two together.
    public var arguments: [String] {
        [String(parentPID), stagingAppPath, targetAppPath]
    }
}
