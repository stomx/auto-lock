# Testing and coverage contract

`./scripts/coverage.sh` is the release gate. It requires **100% line coverage**
for deterministic product logic and fails closed if the scope is empty or a
single executable line is missed.

## Included at 100%

- `Sources/AutoLockCore/**`: proximity, wake, version, update, Keychain ACL,
  typing and rollback decisions.
- `Sources/AutoLockKit/**` except `BLEScanner.swift`: controller state changes,
  settings persistence, release parsing, checksum parsing and update flow.
- `Sources/AutoLockSystemAdapters/StagedAppVerifier.swift`: staged bundle ID,
  version, build, architecture, executable and signature-boundary validation.
- `Sources/AutoLockSystemAdapters/SelfUpdateCoordinator.swift`: download,
  staging, verification, helper creation, cleanup and termination ordering.

These tests assert outcomes and side effects, including failure and recovery;
they do not exist merely to execute lines.

## Deliberately outside the percentage

- `Sources/AutoLock/**`: SwiftUI/AppKit composition and visual rendering.
- `BLEScanner.swift`: CoreBluetooth delegate bridge.
- `KeychainStore.swift`, `ScreenLocker.swift`, `WakeController.swift`,
  `UnlockTrigger.swift`, the native I/O inside `UpdateAdapters.swift`, and
  `NativeCodeSignatureChecker.swift`: native macOS/network/process boundaries.

Executing those boundaries in unit tests would mutate the user's Keychain,
lock or wake the machine, post real password keystrokes, terminate the test
process, or depend on Bluetooth/network state. Their decisions are extracted
into the included modules; the remaining bridges are verified through safe
temporary-bundle integration tests, shell-script execution tests, strict
release builds, signature checks, and focused manual release checks.

The raw LLVM percentage remains a diagnostic metric and must not be presented
as the coverage contract because it mixes product code, native boundaries and
test code. The release claim is specifically: **100% of deterministic product
logic under the documented scope**.
