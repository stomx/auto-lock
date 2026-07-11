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
        if kill -0 "$PARENT" 2>/dev/null; then
            exit 1
        fi

        # 2) Keep a same-volume backup, then atomically rename the staged app.
        #    Never delete the only known-good app before the new one is live.
        BACKUP="${TARGET}.autolock-backup"
        MARKER="${TARGET}.autolock-health"
        rm -rf "$BACKUP"
        rm -f "$MARKER"
        /bin/mv "$TARGET" "$BACKUP" || exit 1
        if ! /bin/mv "$STAGING" "$TARGET"; then
            /bin/mv "$BACKUP" "$TARGET"
            exit 1
        fi

        # 3) Drop quarantine so Gatekeeper doesn't re-prompt on relaunch.
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null

        # 4) Launch the new executable with a health-marker argument. The app
        #    writes the marker immediately before entering SwiftUI's main loop.
        "$TARGET/Contents/MacOS/AutoLock" --post-update-marker "$MARKER" >/dev/null 2>&1 &
        NEW_PID=$!
        i=0
        while [ ! -f "$MARKER" ] && kill -0 "$NEW_PID" 2>/dev/null && [ "$i" -lt 100 ]; do
            sleep 0.1
            i=$((i + 1))
        done

        if [ -f "$MARKER" ]; then
            rm -rf "$BACKUP"
            rm -f "$MARKER"
            rm -rf "$(dirname "$STAGING")"
            exit 0
        fi

        # 5) New app did not reach its entry point: stop it, restore the backup,
        #    and relaunch the known-good app.
        kill "$NEW_PID" 2>/dev/null || true
        rm -rf "$TARGET"
        /bin/mv "$BACKUP" "$TARGET" || exit 1
        /usr/bin/open "$TARGET"
        rm -rf "$(dirname "$STAGING")"
        exit 1
        """
    }
}
