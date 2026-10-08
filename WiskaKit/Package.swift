// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WiskaKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "WiskaKit", targets: ["Core", "Hotkey", "Audio", "SpeechToText", "Cleanup", "Injection", "Dictation", "HUD", "Preferences", "Parakeet", "History"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7"),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Hotkey", dependencies: ["Core"]),
        .target(name: "Audio", dependencies: ["Core"]),
        .target(name: "SpeechToText", dependencies: ["Core"]),
        .target(name: "Cleanup", dependencies: ["Core"]),
        .target(name: "Injection", dependencies: ["Core"]),
        .target(name: "Dictation", dependencies: ["Core"]),
        .target(name: "HUD", dependencies: ["Core"]),
        .target(name: "Preferences", dependencies: ["Core"]),
        .target(name: "History", dependencies: ["Core"]),
        .target(name: "Parakeet", dependencies: [
            "Core", .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "HotkeyTests", dependencies: ["Hotkey"]),
        .testTarget(name: "AudioTests", dependencies: ["Audio"]),
        .testTarget(name: "SpeechToTextTests", dependencies: ["SpeechToText"]),
        .testTarget(name: "CleanupTests", dependencies: ["Cleanup"]),
        .testTarget(name: "InjectionTests", dependencies: ["Injection"]),
        .testTarget(name: "DictationTests", dependencies: ["Dictation"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"]),
        .testTarget(name: "ParakeetTests", dependencies: ["Parakeet"]),
        .testTarget(name: "HistoryTests", dependencies: ["History"]),
        .testTarget(name: "HUDTests", dependencies: ["HUD"]),
    ]
)
