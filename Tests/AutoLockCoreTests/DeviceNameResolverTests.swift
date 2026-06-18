import Testing
import Foundation
@testable import AutoLockCore

/// `DeviceNameResolver.resolve` is the device-name selection logic extracted
/// from `BLEScanner.didDiscover`. The original `peripheral.name ?? advName ??
/// existing` chain discarded a real advertised name whenever `peripheral.name`
/// was the literal `"Unknown"`, hiding the device from the picker (which filters
/// out `"Unknown"`). The resolver treats nil / empty / `"Unknown"` uniformly as
/// "no real name" and prefers the first genuine candidate.
@Suite struct DeviceNameResolverTests {

    // 1. peripheral.name이 실명이면 그대로 사용.
    @Test func peripheralNameWins() {
        let name = DeviceNameResolver.resolve(peripheralName: "Jay's Watch", advertisedName: nil, existingName: nil)
        #expect(name == "Jay's Watch")
    }

    // 2. 핵심 버그: peripheral.name == "Unknown"이면 advName 실명을 살린다.
    @Test func unknownPeripheralFallsToAdvertised() {
        let name = DeviceNameResolver.resolve(peripheralName: "Unknown", advertisedName: "nRF Beacon", existingName: nil)
        #expect(name == "nRF Beacon")
    }

    // 3. peripheral.name nil + advName 실명 → advName.
    @Test func advertisedNameUsedWhenPeripheralNil() {
        let name = DeviceNameResolver.resolve(peripheralName: nil, advertisedName: "Pixel", existingName: nil)
        #expect(name == "Pixel")
    }

    // 4. 빈 문자열도 실명 후보에서 제외.
    @Test func emptyStringsAreNotRealNames() {
        let name = DeviceNameResolver.resolve(peripheralName: "", advertisedName: "  Galaxy  ".trimmingCharacters(in: .whitespaces), existingName: nil)
        #expect(name == "Galaxy")
    }

    // 5. 새 실명이 없으면 이전에 봤던 이름을 유지한다.
    @Test func keepsExistingWhenNoNewName() {
        let name = DeviceNameResolver.resolve(peripheralName: "Unknown", advertisedName: nil, existingName: "iPhone")
        #expect(name == "iPhone")
    }

    // 6. 아무 실명도 없으면 "Unknown"으로 표기(picker가 거른다).
    @Test func fallsBackToUnknown() {
        let name = DeviceNameResolver.resolve(peripheralName: nil, advertisedName: nil, existingName: nil)
        #expect(name == "Unknown")
    }

    // 7. existing이 "Unknown"이어도 새 실명이 들어오면 갱신.
    @Test func realNameUpgradesExistingUnknown() {
        let name = DeviceNameResolver.resolve(peripheralName: nil, advertisedName: "Watch", existingName: "Unknown")
        #expect(name == "Watch")
    }

    // 8. peripheral 실명이 advName보다 우선.
    @Test func peripheralPreferredOverAdvertised() {
        let name = DeviceNameResolver.resolve(peripheralName: "Real", advertisedName: "Adv", existingName: nil)
        #expect(name == "Real")
    }
}
