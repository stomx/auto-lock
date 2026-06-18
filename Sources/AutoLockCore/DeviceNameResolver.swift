import Foundation

/// Resolves the display name for a discovered BLE device, extracted from
/// `BLEScanner.didDiscover`.
///
/// The original `peripheral.name ?? advName ?? existing` chain treated only
/// `nil` as "missing", so a `peripheral.name` of the literal `"Unknown"` won
/// the chain and discarded a real name carried in the advertisement / scan
/// response — leaving the device invisible in the picker, which filters
/// `"Unknown"` out. This resolver treats `nil`, empty, and `"Unknown"`
/// uniformly as "no real name" and prefers the first genuine candidate,
/// falling back to a previously-seen name, then finally to `"Unknown"`.
public enum DeviceNameResolver {
    public static let placeholder = "Unknown"

    public static func resolve(
        peripheralName: String?,
        advertisedName: String?,
        existingName: String?
    ) -> String {
        // First genuine name among the live candidates, in priority order.
        if let real = [peripheralName, advertisedName].compactMap(realName).first {
            return real
        }
        // No fresh real name — keep whatever real name we stored before.
        if let priorReal = realName(existingName) {
            return priorReal
        }
        return placeholder
    }

    /// A name counts as "real" only if it is non-nil, non-empty, and not the
    /// `"Unknown"` placeholder.
    private static func realName(_ candidate: String?) -> String? {
        guard let candidate, !candidate.isEmpty, candidate != placeholder else { return nil }
        return candidate
    }
}
