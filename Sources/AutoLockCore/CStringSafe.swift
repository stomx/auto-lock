import Foundation

/// Null-safe wrapper around `String(cString:)`.
///
/// `String(cString:)` is undefined behaviour when handed a NULL pointer, yet
/// several C APIs legitimately return NULL — most notably `dlerror()`, which
/// returns NULL when there is no pending error. `ScreenLocker` logged
/// `String(cString: dlerror())` directly, a latent crash. This helper returns
/// `fallback` for NULL and decodes the C string otherwise.
public enum CStringSafe {
    public static func string(from pointer: UnsafePointer<CChar>?, fallback: String) -> String {
        guard let pointer else { return fallback }
        return String(cString: pointer)
    }
}
