import Foundation

/// Builds the detached shell script that swaps the running app bundle for a
/// freshly-downloaded one and relaunches it. Pure value type — it only produces
/// the script text and the argument vector; spawning the process (and the
/// `NSApp.terminate` that follows) is the executable's job.
///
/// Why a detached script rather than in-process file ops: the running app can't
/// overwrite its own bundle while it's mapped in. So we hand a tiny `/bin/sh`
/// program the work — it waits for *this* process to die, replaces the bundle,
/// strips quarantine, and relaunches — then we exit so it can proceed.
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

    /// Single-quote a path for safe embedding in `/bin/sh`. Wraps in `'…'` and
    /// escapes any embedded single quote as `'\''`, so spaces, `$`, `;`, and
    /// other shell metacharacters in the path can't break out.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The `/bin/sh` script body. Positional args are quoted at the call site
    /// (see `arguments`); inside the script we still quote `"$VAR"` expansions
    /// so paths with spaces survive.
    public var scriptText: String {
        """
        #!/bin/sh
        # AutoLock self-update helper — generated, runs detached from the app.
        # $1=parent_pid  $2=staging_app  $3=target_app
        PARENT="$1"; STAGING="$2"; TARGET="$3"

        # 1) Wait (≤30s) for the running app to exit so the bundle is free.
        i=0
        while kill -0 "$PARENT" 2>/dev/null && [ "$i" -lt 300 ]; do
            sleep 0.1
            i=$((i + 1))
        done

        # 2) Replace the bundle in place. ditto preserves perms/xattrs.
        rm -rf "$TARGET" || exit 1
        /usr/bin/ditto "$STAGING" "$TARGET" || exit 1

        # 3) Drop quarantine so Gatekeeper doesn't re-prompt on relaunch.
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null

        # 4) Relaunch the updated app, then clean up staging + this script.
        /usr/bin/open "$TARGET"
        rm -rf "$STAGING"
        rm -f "$0"
        """
    }

    /// The positional argument vector the helper expects ($1..$3), pre-quoted
    /// so the executable can pass them verbatim to `/bin/sh <script> <args…>`.
    public var arguments: [String] {
        [String(parentPID), stagingAppPath, targetAppPath]
    }
}
