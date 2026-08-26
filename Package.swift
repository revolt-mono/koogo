// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AgentTracker",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AgentTracker", targets: ["AgentTracker"])
    ],
    dependencies: [
        .package(url: "https://github.com/markiv/SwiftUI-Shimmer.git", from: "1.5.1")
    ],
    targets: [
        .executableTarget(
            name: "AgentTracker",
            dependencies: [
                .product(name: "Shimmer", package: "SwiftUI-Shimmer")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AgentTrackerTests", dependencies: ["AgentTracker"])
    ]
)
