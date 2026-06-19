// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "watson-recorder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "watson-recorder",
            targets: ["watson_recorder"]
        )
    ],
    targets: [
        .executableTarget(
            name: "watson_recorder",
            dependencies: [],
            path: "Sources/watson_recorder"
        )
    ]
)
