// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Suri",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Suri", targets: ["Suri"])
    ],
    targets: [
        .executableTarget(name: "Suri")
    ]
)
