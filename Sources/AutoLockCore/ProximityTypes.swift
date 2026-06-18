import Foundation

public enum ProximityState: String {
    case unknown
    case near       // a tracked device is comfortably in range
    case borderline // RSSI between unlock and lock thresholds
    case away       // tracked devices missing or below lock threshold
}

/// Why we made the most recent state-machine transition. Kept as a domain
/// enum so the controller stays UI/locale-agnostic — `MenuView` decides how
/// each case is rendered to the user.
public enum LockReason: Equatable {
    case signalStaleSeconds(Int)   // device hasn't advertised for N seconds
    case signalWeak                // RSSI dropped below the lock threshold
    case signalCrashed             // RSSI dropped well below threshold (instant lock)
    case deviceUnseen              // no tracked device discovered at all

    /// Stable, ASCII identifier for log lines. UI strings live in MenuView.
    public var logDescription: String {
        switch self {
        case .signalStaleSeconds(let s): return "stale=\(s)s"
        case .signalWeak:                return "weak"
        case .signalCrashed:             return "crashed"
        case .deviceUnseen:              return "unseen"
        }
    }
}

/// User-facing status of the controller. Renders to a localized string in
/// the view layer so the controller doesn't carry localized text or
/// presentation timing information.
public enum ControllerStatus: Equatable {
    case idle                           // toggle off
    case awaitingDevice                 // toggle on, no tracked device
    case watching                       // running, no concerns
    case countdown(reason: LockReason, secondsLeft: Int)
    case instantLock(reason: LockReason)
    case locked(reason: LockReason)
    /// `ScreenLocking.lock()` reported failure (e.g. the private lock symbol
    /// was unavailable). We must NOT present this as a successful lock; the
    /// controller keeps retrying on subsequent ticks.
    case lockFailed(reason: LockReason)
}
