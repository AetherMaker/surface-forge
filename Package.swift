// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SurfaceForge",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "SurfaceForge",
            targets: ["SurfaceForge"]
        ),
    ],
    targets: [
        .target(
            name: "SurfaceForge"
        ),
        .testTarget(
            name: "SurfaceForgeTests",
            dependencies: ["SurfaceForge"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
