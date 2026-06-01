import Foundation

/// A device the user has chosen to track for proximity. Persisted to
/// UserDefaults via Settings, so it is Codable.
public struct TrackedDevice: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A device currently visible to the BLE scanner, with its smoothed signal.
public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var smoothedRssi: Double
    public var lastSeen: Date

    public init(id: UUID, name: String, smoothedRssi: Double, lastSeen: Date) {
        self.id = id
        self.name = name
        self.smoothedRssi = smoothedRssi
        self.lastSeen = lastSeen
    }
}
