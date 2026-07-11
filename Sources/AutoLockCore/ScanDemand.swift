/// Independent reasons that can keep BLE scanning active.
///
/// Device selection must work even when proximity monitoring is disabled, and
/// dismissing the picker must not stop a scan that monitoring still needs.
public enum ScanPurpose: Hashable, Sendable {
    case proximityMonitoring
    case deviceSelection
}

/// Tracks scan demand from multiple clients without letting one client cancel
/// another client's request.
public struct ScanDemand: Sendable {
    private var purposes: Set<ScanPurpose> = []

    public init() {}

    public var isRequested: Bool { !purposes.isEmpty }

    public mutating func request(_ purpose: ScanPurpose) {
        purposes.insert(purpose)
    }

    public mutating func cancel(_ purpose: ScanPurpose) {
        purposes.remove(purpose)
    }
}
