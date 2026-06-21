import Foundation

/// The Bluetooth adapter state the app cares about, as a pure domain enum so no
/// consumer needs CoreBluetooth's `CBManagerState`. `BLEScanner` maps the
/// framework value to this and publishes it, keeping the CoreBluetooth type
/// behind the Kit boundary — UI, diagnostics, and the permission prompt read
/// this instead.
///
/// The cases mirror the `CBManagerState` ones the app handles; the mapping
/// lives in the Kit adapter (`BluetoothPowerState.init(rawState:)` takes a raw
/// Int so this stays Foundation-only and unit-testable without CoreBluetooth).
public enum BluetoothPowerState: Equatable, Sendable {
    case unknown        // not yet reported by the system
    case resetting      // the connection with the system service was lost
    case unsupported    // this Mac has no BLE
    case unauthorized   // the user hasn't granted Bluetooth permission
    case poweredOff     // Bluetooth is off
    case poweredOn      // ready to scan

    /// Map from a `CBManagerState` raw value. CoreBluetooth's `CBManagerState`
    /// is an `Int`-backed enum with stable cases:
    /// 0=unknown 1=resetting 2=unsupported 3=unauthorized 4=poweredOff 5=poweredOn.
    /// Taking the raw `Int` keeps this initializer in Foundation-only Core; the
    /// Kit adapter calls it as `BluetoothPowerState(rawState: central.state.rawValue)`.
    public init(rawState: Int) {
        switch rawState {
        case 1: self = .resetting
        case 2: self = .unsupported
        case 3: self = .unauthorized
        case 4: self = .poweredOff
        case 5: self = .poweredOn
        default: self = .unknown   // 0 and any future/unexpected value → unknown
        }
    }

    /// Whether the adapter is ready to scan.
    public var isReady: Bool { self == .poweredOn }

    /// Whether this state warrants a one-time permission/setup prompt
    /// (unauthorized / off / unsupported). `.unknown`/`.resetting`/`.poweredOn`
    /// do not.
    public var needsUserAction: Bool {
        switch self {
        case .unauthorized, .poweredOff, .unsupported: return true
        case .unknown, .resetting, .poweredOn: return false
        }
    }
}
