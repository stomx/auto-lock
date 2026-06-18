import Foundation

/// Monotonic time source for all proximity timing.
///
/// Every age/deadline in the proximity state machine is a *difference* of two
/// instants (`now - lastSeen`, `deadline - now`). Previously those instants
/// came from `Date()` — the wall clock — so an NTP correction, manual clock
/// change, or large sleep/wake adjustment could make a still-present device
/// look long-absent (spurious instant-lock) or a departed device look fresh.
///
/// `now()` returns a `Date` derived from `ProcessInfo.systemUptime`, which
/// advances monotonically and is immune to wall-clock changes. The result is a
/// `Date` only so the existing `Date`-typed snapshot API stays unchanged — it
/// is NOT a calendar date and must only ever be used in differences. Both ends
/// of every subtraction (device `lastSeen` and the evaluation `now`) must come
/// from this clock so they share one timeline.
public enum MonotonicClock {
    public static func now() -> Date {
        // systemUptime is seconds since boot; anchoring it to the reference
        // date yields a Date whose *differences* equal real elapsed seconds.
        Date(timeIntervalSinceReferenceDate: ProcessInfo.processInfo.systemUptime)
    }
}
