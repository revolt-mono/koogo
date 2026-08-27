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
        .package(url: "https://github.com/markiv/SwiftUI-Shimmer.git", from: "1.5.1")
    ],
    targets: [
        .executableTarget(
            name: "Koogo",
            dependencies: [
                .product(name: "Shimmer", package: "SwiftUI-Shimmer")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "KoogoTests", dependencies: ["Koogo"]),
    ]
)
