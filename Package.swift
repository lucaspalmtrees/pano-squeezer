// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "pano-squeezer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PanoSqueezer", targets: ["PanoSqueezer"]),
        .executable(name: "pano-squeezer-cli", targets: ["pano-squeezer-cli"]),
        .library(name: "PanoSqueezerCore", targets: ["PanoSqueezerCore"]),
    ],
    targets: [
        // Pure logic, Foundation only (also builds on Linux).
        .target(name: "PanoSqueezerCore"),
        // Command line tool for testing.
        .executableTarget(name: "pano-squeezer-cli", dependencies: ["PanoSqueezerCore"]),
        // SwiftUI app (macOS only, stub elsewhere).
        .executableTarget(name: "PanoSqueezer", dependencies: ["PanoSqueezerCore"]),
        .testTarget(name: "PanoSqueezerCoreTests", dependencies: ["PanoSqueezerCore"]),
    ]
)
