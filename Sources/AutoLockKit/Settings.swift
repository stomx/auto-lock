import Foundation
import Combine
import AutoLockCore

// MainActor-isolated: Settings is an ObservableObject driving SwiftUI and is
// only ever read/written from the main actor (MenuView, the @MainActor
// ProximityController, and BLEScanner's main-queue callbacks). Isolating it
// makes the `shared` singleton concurrency-safe under Swift 6 without bolting
// on locks that wouldn't match the observable model.
@MainActor
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
    /// Range: 40~100 in 5-step increments.
    ///
    /// Backed by a private `@Published` so the *only* value ever stored or
    /// published is already clamped — a computed `didSet`-clamp would transiently
    /// publish the raw out-of-range value first. The objectWillChange plumbing
    /// is forwarded manually so SwiftUI still re-renders.
    private var _thresholdMagnitude: Int
    public var thresholdMagnitude: Int {
        get { _thresholdMagnitude }
        set {
            let clamped = LockSettingBounds.clampThresholdMagnitude(newValue)
            objectWillChange.send()
            _thresholdMagnitude = clamped
            defaults.set(clamped, forKey: Keys.thresholdMagnitude)
        }
    }

    /// Advertising-silence tolerance before the lock countdown starts.
    private var _gracePeriodSeconds: Int
    public var gracePeriodSeconds: Int {
        get { _gracePeriodSeconds }
        set {
            let clamped = LockSettingBounds.clampGracePeriodSeconds(newValue)
            objectWillChange.send()
            _gracePeriodSeconds = clamped
            defaults.set(clamped, forKey: Keys.signalLossToleranceSeconds)
        }
    }

    /// Visible countdown duration after an away condition is confirmed.
    private var _countdownSeconds: Int
    public var countdownSeconds: Int {
        get { _countdownSeconds }
        set {
            let clamped = LockSettingBounds.clampCountdownSeconds(newValue)
            objectWillChange.send()
            _countdownSeconds = clamped
            defaults.set(clamped, forKey: Keys.countdownSeconds)
        }
    }

    public var rssiThreshold: Int { -thresholdMagnitude }
    public var definitiveAwayThreshold: Int { rssiThreshold - LockTuning.definitiveAwayMarginDBm }

    private enum Keys {
        static let devices = "trackedDevices"
        static let enabled = "enabled"
        static let wakeOnProximity = "wakeOnProximity"
        static let autoUnlock = "autoUnlock"
        static let thresholdMagnitude = "thresholdMagnitude"
        // New keys intentionally avoid reviving stale values from the old,
        // removed `gracePeriodSeconds` slider.
        static let signalLossToleranceSeconds = "signalLossToleranceSeconds"
        static let countdownSeconds = "countdownSeconds"
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
        let storedMag = defaults.object(forKey: Keys.thresholdMagnitude) as? Int
            ?? LockSettingBounds.defaultThresholdMagnitude
        self._thresholdMagnitude = LockSettingBounds.clampThresholdMagnitude(storedMag)
        let storedGrace = defaults.object(forKey: Keys.signalLossToleranceSeconds) as? Int
            ?? LockSettingBounds.defaultGracePeriodSeconds
        self._gracePeriodSeconds = LockSettingBounds.clampGracePeriodSeconds(storedGrace)
        let storedCountdown = defaults.object(forKey: Keys.countdownSeconds) as? Int
            ?? LockSettingBounds.defaultCountdownSeconds
        self._countdownSeconds = LockSettingBounds.clampCountdownSeconds(storedCountdown)
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
