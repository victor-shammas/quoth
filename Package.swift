// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "quoth",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // WhisperKit, renamed argmax-oss-swift. 1.1.0 is the first release with
        // argmax-oss-swift#514: before it, any transcription with promptTokens
        // came back empty, which the dictionary's example sentence relies on.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
        // In-app updates (#50). A binary framework: scripts/build-app.sh
        // embeds it in Quoth.app/Contents/Frameworks and signs it.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        // Pure logic, Foundation only (ADR-007): gesture rules, the
        // dictionary, voice commands, settings values, the model catalog.
        .target(name: "QuothDomain"),
        // macOS behind small types (ADR-007): the microphone, the hotkey
        // tap, text insertion, focus, permissions, and what the two
        // editions do differently.
        .target(
            name: "QuothPlatform",
            dependencies: ["QuothDomain"]
        ),
        // Speech recognition: WhisperKit, its tuning, language detection,
        // and the models on disk.
        .target(
            name: "QuothSpeech",
            dependencies: [
                "QuothDomain",
                "QuothPlatform",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        // All behaviour: capture, hotkey, transcription, pipeline, settings, UI.
        .target(
            name: "QuothCore",
            dependencies: [
                "QuothDomain",
                "QuothPlatform",
                "QuothSpeech",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        // The direct edition's entry point: one call into QuothCore. Its
        // executable is Quoth.app/Contents/MacOS/quoth (scripts/build-app.sh).
        .executableTarget(
            name: "quoth",
            dependencies: ["QuothCore"]
        ),
        // The transcription benchmark, not shipped in Quoth.app:
        // swift run -c release quoth-bench <folder of .wav recordings>
        .executableTarget(
            name: "quoth-bench",
            dependencies: [
                "QuothCore",
                "QuothDomain",
                "QuothPlatform",
                "QuothSpeech",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Unit tests against QuothCore.
        .testTarget(
            name: "QuothTests",
            dependencies: [
                "QuothCore",
                "QuothDomain",
                "QuothPlatform",
                "QuothSpeech",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        // Unit tests for the benchmark's metrics.
        .testTarget(
            name: "QuothBenchTests",
            dependencies: ["quoth-bench"]
        ),
    ]
)
