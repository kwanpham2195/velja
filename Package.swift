// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Velja",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Velja", targets: ["Velja"]),
    ],
    targets: [
        // Link routing logic with no AppKit dependency, so it can be unit tested.
        .target(name: "VeljaCore"),
        // The menu bar app: Apple event handling, browser picker, settings window.
        .executableTarget(name: "Velja", dependencies: ["VeljaCore"]),
        .testTarget(name: "VeljaCoreTests", dependencies: ["VeljaCore"]),
    ]
)
