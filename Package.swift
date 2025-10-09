// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SVGUIView",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "SVGUIView",
            targets: ["SVGUIView"]
        ),
        .library(
            name: "SVGView",
            targets: ["SVGView"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.51.2"),
    ],
    targets: [
        .target(name: "_SPI"),
        .target(name: "_ICU"),
        .target(name: "_CShims"),
        .target(
            name: "SVGUIView",
            dependencies: ["_SPI", "_ICU", "_CShims"]
        ),
        .target(
            name: "SVGView",
            dependencies: ["SVGUIView"]
        ),
        .testTarget(
            name: "SVGUIViewTests",
            dependencies: ["SVGUIView"],
            resources: [.process("assets")]
        ),
    ]
)
