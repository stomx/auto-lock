import Foundation
import AutoLockCore

/// Generates the detached `/bin/sh` helper that swaps the running app bundle
/// for a freshly-downloaded one and relaunches it. This is update *mechanism*
/// (a concrete shell program for a concrete OS), so it lives in the wiring
/// layer rather than the pure domain — `SelfUpdatePlan` (Core) only describes
/// *what* to swap; this turns that plan into *how*.
///
/// Paths are never interpolated into this text: they arrive as the helper's
/// positional arguments (`SelfUpdatePlan.arguments` → `Process.arguments`), and
/// the script reads them back as quoted `"$1".."$3"`. So the `$1=pid
/// $2=staging $3=target` order here must match `SelfUpdatePlan.arguments`;
/// `SelfUpdateScriptTests` pins that contract.
public enum SelfUpdateScript {
    /// The `/bin/sh` script body for `plan`. The script takes the paths as
    /// positional args ($1..$3) and quotes every `"$VAR"` expansion so paths
    /// with spaces or shell metacharacters survive without any caller-side
    /// quoting.
    public static func text(for plan: SelfUpdatePlan) -> String {
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
}
