// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenGlass",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "OpenGlass",
            targets: ["OpenGlass"],
        ),
    ],
    targets: [
        .target(
            name: "OpenGlass",
        ),
    ],
)
