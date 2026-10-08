// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SecureWisprKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SecureWisprKit", targets: ["Core", "Hotkey", "Audio"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Hotkey", dependencies: ["Core"]),
        .target(name: "Audio", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "HotkeyTests", dependencies: ["Hotkey"]),
        .testTarget(name: "AudioTests", dependencies: ["Audio"]),
    ]
)
