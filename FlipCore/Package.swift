// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlipCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "FlipCore", targets: ["FlipCore"]),
    ],
    targets: [
        .target(name: "FlipCore"),
        .testTarget(name: "FlipCoreTests", dependencies: ["FlipCore"]),
    ]
)
