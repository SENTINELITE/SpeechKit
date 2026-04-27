// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SpeechKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "SpeechKit",
            targets: ["SpeechKit"]
        ),
    ],
    targets: [
        .target(
            name: "SpeechKit"
        ),
        .testTarget(
            name: "SpeechKitTests",
            dependencies: ["SpeechKit"]
        ),
    ]
)
