// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoLock",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AutoLock", targets: ["AutoLock"])
    ],
    targets: [
        // Pure domain + decision logic. Foundation only — no CoreBluetooth,
        // AppKit, or system calls — so it can be unit tested without a host app.
        .target(
            name: "AutoLockCore",
            path: "Sources/AutoLockCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Wiring layer: BLE scanning, settings, and the proximity controller.
        // May use AppKit/CoreBluetooth/Combine/SwiftUI, but takes all system
        // side effects via injected protocols so the controller is testable.
        .target(
            name: "AutoLockKit",
            dependencies: ["AutoLockCore"],
            path: "Sources/AutoLockKit"
        ),
        // Concrete macOS boundaries (Security, AppKit, IOKit, update I/O).
        // Kept out of the executable so verification and adapter policy can be
        // tested without launching the menu-bar application.
        .target(
            name: "AutoLockSystemAdapters",
            dependencies: ["AutoLockKit", "AutoLockCore"],
            path: "Sources/AutoLockSystemAdapters"
        ),
        .executableTarget(
            name: "AutoLock",
            dependencies: ["AutoLockKit", "AutoLockSystemAdapters"],
            path: "Sources/AutoLock"
        ),
        .testTarget(
            name: "AutoLockCoreTests",
            dependencies: ["AutoLockCore"],
            path: "Tests/AutoLockCoreTests"
        ),
        .testTarget(
            name: "AutoLockKitTests",
            dependencies: ["AutoLockKit"],
            path: "Tests/AutoLockKitTests"
        ),
        .testTarget(
            name: "AutoLockSystemAdaptersTests",
            dependencies: ["AutoLockSystemAdapters", "AutoLockKit", "AutoLockCore"],
            path: "Tests/AutoLockSystemAdaptersTests"
        ),
    ]
)
