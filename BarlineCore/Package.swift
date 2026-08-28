// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BarlineCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BarlineCore", targets: ["BarlineCore"]),
    ],
    targets: [
        .target(name: "BarlineCore"),
        .testTarget(name: "BarlineCoreTests", dependencies: ["BarlineCore"]),
    ],
    swiftLanguageModes: [.v6]
)
