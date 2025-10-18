// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SVGUIView",
  platforms: [
    .iOS(.v16)
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
  targets: [
    .target(name: "_SPI"),
    .target(name: "_ICU"),
    .target(name: "_CShims"),
    .target(
      name: "SVGUIView",
      dependencies: ["_SPI", "_ICU", "_CShims", "_CSSParser"],
    ),
    .target(
      name: "SVGView",
      dependencies: ["SVGUIView"],
    ),
    .target(
      name: "_CSSParser"
    ),
    .testTarget(
      name: "SVGUIViewTests",
      dependencies: ["SVGUIView"],
      resources: [.process("assets")],
    ),
    .testTarget(
      name: "_CSSParserTests",
      dependencies: ["_CSSParser"],
      resources: [.process("assets")],
    ),
  ]
)
