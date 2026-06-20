import Foundation

/// Decides whether the running app can replace its own bundle on disk. Pure —
/// path classification plus an injected writability probe — so the executable
/// just supplies `Bundle.main.bundleURL` and a `FileManager`-backed closure.
public enum InstallLocation {

    public enum Verdict: Equatable {
        /// Safe to swap the bundle in place (writable, not translocated).
        case replaceable
        /// macOS is running us from a read-only translocated copy (Gatekeeper
        /// App Translocation); the real bundle path is hidden, so self-update
        /// can't target it. User must move the app out of quarantine first.
        case translocated
        /// The bundle path is real but not writable by this user (e.g. a
        /// system-managed install). Self-update would need elevation, which we
        /// refuse — fall back to manual install.
        case notWritable
    }

    /// True when `path` looks like a Gatekeeper App Translocation mount: a
    /// read-only randomized location under `AppTranslocation`. Pure string test
    /// (no Security.framework dependency) — robust enough since the OS always
    /// routes translocated apps through this well-known path component.
    public static func isTranslocated(path: String) -> Bool {
        path.contains("/AppTranslocation/")
    }

    /// Classify a bundle URL. `isWritable` is injected (the executable passes a
    /// `FileManager.isWritableFile(atPath:)`-backed probe) so this stays pure
    /// and unit-testable. Translocation is checked first: a translocated path
    /// is never a valid replace target even if it reports writable.
    public static func classify(
        bundlePath: String,
        isWritable: (String) -> Bool
    ) -> Verdict {
        if isTranslocated(path: bundlePath) {
            return .translocated
        }
        return isWritable(bundlePath) ? .replaceable : .notWritable
    }
}
