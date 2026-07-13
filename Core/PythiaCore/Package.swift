// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PythiaCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PythiaCore", targets: ["PythiaCore"])
    ],
    targets: [
        .target(name: "PythiaCore"),
        .testTarget(name: "PythiaCoreTests", dependencies: ["PythiaCore"])
    ]
)
