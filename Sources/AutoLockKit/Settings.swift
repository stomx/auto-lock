import Foundation
import Combine
import AutoLockCore

public final class Settings: ObservableObject {
    public static let shared = Settings()

    /// 영속화 대상 UserDefaults. 테스트에서 격리된 suite를 주입할 수 있도록 보관한다.
    private let defaults: UserDefaults

    @Published public var trackedDevices: [TrackedDevice] {
        didSet { persistDevices() }
    }
    @Published public var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled) }
    }
    @Published public var wakeOnProximity: Bool {
        didSet { defaults.set(wakeOnProximity, forKey: Keys.wakeOnProximity) }
    }
    /// When the screen is locked and a tracked device returns, type the saved
    /// password into loginwindow. Requires Keychain entry + Accessibility.
    @Published public var autoUnlock: Bool {
        didSet { defaults.set(autoUnlock, forKey: Keys.autoUnlock) }
    }
    /// Slider exposes the magnitude (positive); the actual RSSI threshold is the negation.
    /// Range: 40~100 in 10-step increments.
    @Published public var thresholdMagnitude: Int {
        didSet { defaults.set(thresholdMagnitude, forKey: Keys.thresholdMagnitude) }
    }
    /// Maximum advertising silence we tolerate before starting the countdown.
    /// Range: 15~60s in 1s steps.
    @Published public var gracePeriodSeconds: Int {
        didSet { defaults.set(gracePeriodSeconds, forKey: Keys.gracePeriod) }
    }

    public var rssiThreshold: Int { -thresholdMagnitude }
    public var definitiveAwayThreshold: Int { rssiThreshold - LockTuning.definitiveAwayMarginDBm }

    private enum Keys {
        static let devices = "trackedDevices"
        static let enabled = "enabled"
        static let wakeOnProximity = "wakeOnProximity"
        static let autoUnlock = "autoUnlock"
        static let thresholdMagnitude = "thresholdMagnitude"
        static let gracePeriod = "gracePeriodSeconds"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        self.gracePeriodSeconds = min(LockTuning.maxGracePeriodSeconds, max(15, storedGrace))
    }

    /// Only one device is supported at a time. Replacing keeps the UI simple
    /// and avoids ambiguity when picking the "best" RSSI from multiple sources.
    public func addDevice(_ device: TrackedDevice) {
        trackedDevices = [device]
    }

    public func removeDevice(id: UUID) {
        trackedDevices.removeAll { $0.id == id }
    }

    private func persistDevices() {
        if let data = try? JSONEncoder().encode(trackedDevices) {
            defaults.set(data, forKey: Keys.devices)
        }
    }
}
