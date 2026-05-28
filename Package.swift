// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoLock",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AutoLock", targets: ["AutoLock"])
    ],
    targets: [
        .executableTarget(
            name: "AutoLock",
            path: "Sources/AutoLock"
        )
    ]
)
