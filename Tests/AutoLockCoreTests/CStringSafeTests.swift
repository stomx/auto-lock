import Testing
import Foundation
@testable import AutoLockCore

/// `CStringSafe.string(from:fallback:)` guards the `String(cString:)` UB that
/// `ScreenLocker` hit when logging `dlerror()`: `dlerror()` may return NULL,
/// and `String(cString: <nil>)` is undefined behaviour. The helper returns a
/// fallback for NULL and decodes the C string otherwise.
@Suite struct CStringSafeTests {

    // 1. NULL pointer → fallback string, no crash.
    @Test func nilPointerReturnsFallback() {
        let s = CStringSafe.string(from: nil, fallback: "unknown error")
        #expect(s == "unknown error")
    }

    // 2. Valid C string → decoded contents.
    @Test func validPointerDecodes() {
        let decoded = "boom".withCString { ptr in
            CStringSafe.string(from: ptr, fallback: "unused")
        }
        #expect(decoded == "boom")
    }

    // 3. Empty C string → empty string (distinct from the NULL fallback).
    @Test func emptyStringDecodesToEmpty() {
        let decoded = "".withCString { ptr in
            CStringSafe.string(from: ptr, fallback: "fallback")
        }
        #expect(decoded == "")
    }
}
