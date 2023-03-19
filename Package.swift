// swift-tools-version: 5.7
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
    dependencies: [
        .package(url: "https://github.com/nnabeyang/SVGView.git", branch: "fix-objects-visibility"),
    ],
    targets: [
        .target(
            name: "SVGUIView",
            dependencies: ["SVGView"]
        ),
        .testTarget(
            name: "SVGUIViewTests",
            dependencies: ["SVGUIView"]
        ),
    ]
)
