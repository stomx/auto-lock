import Foundation
import Combine

struct TrackedDevice: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
}

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var trackedDevices: [TrackedDevice] {
        didSet { persistDevices() }
    }
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }
    @Published var wakeOnProximity: Bool {
        didSet { UserDefaults.standard.set(wakeOnProximity, forKey: Keys.wakeOnProximity) }
    }
    /// When the screen is locked and a tracked device returns, type the saved
    /// password into loginwindow. Requires Keychain entry + Accessibility.
    @Published var autoUnlock: Bool {
        didSet { UserDefaults.standard.set(autoUnlock, forKey: Keys.autoUnlock) }
    }
    /// Slider exposes the magnitude (positive); the actual RSSI threshold is the negation.
    /// Range: 40~100 in 10-step increments.
    @Published var thresholdMagnitude: Int {
        didSet { UserDefaults.standard.set(thresholdMagnitude, forKey: Keys.thresholdMagnitude) }
    }
    /// Maximum advertising silence we tolerate before starting the countdown.
    /// Range: 15~60s in 1s steps.
    @Published var gracePeriodSeconds: Int {
        didSet { UserDefaults.standard.set(gracePeriodSeconds, forKey: Keys.gracePeriod) }
    }

    let definitiveAwayMargin: Int = 10

    var rssiThreshold: Int { -thresholdMagnitude }
    var lockThreshold: Int { rssiThreshold }
    var unlockThreshold: Int { rssiThreshold }
    var definitiveAwayThreshold: Int { rssiThreshold - definitiveAwayMargin }

    private enum Keys {
        static let devices = "trackedDevices"
        static let enabled = "enabled"
        static let wakeOnProximity = "wakeOnProximity"
        static let autoUnlock = "autoUnlock"
        static let thresholdMagnitude = "thresholdMagnitude"
        static let gracePeriod = "gracePeriodSeconds"
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.devices),
           let decoded = try? JSONDecoder().decode([TrackedDevice].self, from: data) {
            self.trackedDevices = decoded
        } else {
            self.trackedDevices = []
        }
        self.enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        self.wakeOnProximity = defaults.object(forKey: Keys.wakeOnProximity) as? Bool ?? true
        self.autoUnlock = defaults.object(forKey: Keys.autoUnlock) as? Bool ?? false
        let storedMag = defaults.object(forKey: Keys.thresholdMagnitude) as? Int ?? 100
        self.thresholdMagnitude = min(100, max(40, storedMag))
        let storedGrace = defaults.object(forKey: Keys.gracePeriod) as? Int ?? 15
        self.gracePeriodSeconds = min(60, max(15, storedGrace))
    }

    /// Only one device is supported at a time. Replacing keeps the UI simple
    /// and avoids ambiguity when picking the "best" RSSI from multiple sources.
    func addDevice(_ device: TrackedDevice) {
        trackedDevices = [device]
    }

    func removeDevice(id: UUID) {
        trackedDevices.removeAll { $0.id == id }
    }

    private func persistDevices() {
        if let data = try? JSONEncoder().encode(trackedDevices) {
            UserDefaults.standard.set(data, forKey: Keys.devices)
        }
    }
}
