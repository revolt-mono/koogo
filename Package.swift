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
        .executableTarget(
            name: "Koogo",
            dependencies: [
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
            // SwiftPM leaves binary frameworks beside the test bundle instead of embedding them.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../..",
                ])
            ]
        ),
    ]
)
