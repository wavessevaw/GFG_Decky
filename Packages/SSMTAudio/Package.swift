// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SSMTAudio",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SSMTAudio", targets: ["SSMTAudio"])],
    dependencies: [.package(path: "../SSMTCore")],
    targets: [
        // Core Audio HAL backend (macOS only). Compiles to an empty module elsewhere.
        .target(name: "SSMTAudio", dependencies: [
            .product(name: "SSMTCore", package: "SSMTCore"),
            .product(name: "SSMTRealtime", package: "SSMTCore"),
        ]),
    ]
)
