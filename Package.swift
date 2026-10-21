// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Koogo",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Koogo", targets: ["Koogo"])
    ],
    dependencies: [
        .package(url: "https://github.com/markiv/SwiftUI-Shimmer.git", from: "1.5.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.1"),
    ],
    targets: [
        // zstd's single-file decoder reads compressed codex rollouts; macos ships no zstd library.
        .target(name: "CZstd", exclude: ["LICENSE"]),
        .executableTarget(
            name: "Koogo",
            dependencies: [
                "CZstd",
                .product(name: "Shimmer", package: "SwiftUI-Shimmer"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            exclude: ["Resources/Koogo.icon"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KoogoTests",
            dependencies: ["Koogo"],
            // swiftpm places binary frameworks beside the test bundle rather than embedding them.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../..",
                ])
            ]
        ),
    ]
)
