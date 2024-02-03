// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SVGUIView",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "SVGUIView",
            targets: ["SVGUIView"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SVGUIView",
            dependencies: []
        ),
        .testTarget(
            name: "SVGUIViewTests",
            dependencies: ["SVGUIView"],
            resources: [.process("assets")]
        ),
    ]
)
