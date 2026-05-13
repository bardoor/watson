// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "watson-recorder",
    platforms: [
        .macOS(.v13)
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
