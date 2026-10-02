// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SSMTCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SSMTCore", targets: ["SSMTCore"]),
        .library(name: "SSMTRealtime", targets: ["SSMTRealtime"]),
    ],
    targets: [
        // Lock-free primitives for the real-time audio thread (C11 atomics).
        .target(name: "SSMTRealtime"),
        // DSP, measurement engine, simulation. No UI, no Core Audio.
        .target(name: "SSMTCore", dependencies: ["SSMTRealtime"]),
        .testTarget(name: "SSMTCoreTests", dependencies: ["SSMTCore", "SSMTRealtime"]),
    ]
)
