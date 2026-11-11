// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Canopy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CanopyKit",
            targets: ["CanopyKit"]
        ),
        .executable(
            name: "Canopy",
            targets: ["Canopy"]
        )
    ],
    targets: [
        .target(
            name: "CanopyKit",
            dependencies: [],
            path: "Sources/CanopyKit",
            resources: [
                .copy("Shaders")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Canopy",
            dependencies: ["CanopyKit"],
            path: "Sources/Canopy",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "CanopyTests",
            dependencies: ["CanopyKit"],
            path: "Tests/CanopyTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
