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
    targets: [
        .executableTarget(name: "AgentTracker"),
        .testTarget(name: "AgentTrackerTests", dependencies: ["AgentTracker"])
    ]
)
