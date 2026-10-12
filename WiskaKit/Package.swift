// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WiskaKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "WiskaKit", targets: ["Core", "Hotkey", "Audio", "SpeechToText", "Cleanup", "Injection", "Dictation", "HUD", "Preferences", "Parakeet", "History", "LocalModel", "KBWhisper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.4"),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Hotkey", dependencies: ["Core"]),
        .target(name: "Audio", dependencies: ["Core"]),
        .target(name: "SpeechToText", dependencies: ["Core"]),
        .target(name: "Cleanup", dependencies: ["Core"]),
        .target(name: "Injection", dependencies: ["Core"]),
        .target(name: "Dictation", dependencies: ["Core"]),
        .target(name: "HUD", dependencies: ["Core"], resources: [.process("Shaders")]),
        .target(name: "Preferences", dependencies: ["Core"]),
        .target(name: "History", dependencies: ["Core"]),
        .target(name: "Parakeet", dependencies: [
            "Core", .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .target(name: "LocalModel", dependencies: [
            "Core",
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ]),
        .binaryTarget(name: "whisper",
                      url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
                      checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"),
        .target(name: "KBWhisper", dependencies: ["Core", "whisper"]),
        .testTarget(name: "KBWhisperTests", dependencies: ["KBWhisper"]),
        .testTarget(name: "LocalModelTests", dependencies: ["LocalModel", "Cleanup"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "HotkeyTests", dependencies: ["Hotkey"]),
        .testTarget(name: "AudioTests", dependencies: ["Audio"]),
        .testTarget(name: "SpeechToTextTests", dependencies: ["SpeechToText"]),
        .testTarget(name: "CleanupTests", dependencies: ["Cleanup"]),
        .testTarget(name: "InjectionTests", dependencies: ["Injection"]),
        .testTarget(name: "DictationTests", dependencies: ["Dictation"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"]),
        .testTarget(name: "ParakeetTests", dependencies: ["Parakeet", "SpeechToText", "Dictation"]),
        .testTarget(name: "HistoryTests", dependencies: ["History"]),
        .testTarget(name: "HUDTests", dependencies: ["HUD"]),
    ]
)
