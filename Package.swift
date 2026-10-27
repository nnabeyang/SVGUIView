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
      name: "SVGCore",
      dependencies: ["_SPI", "_ICU", "_CShims", "_CSSParser", "_SelectorParser"],
    ),
    .target(
      name: "SVGRenderCG",
      dependencies: ["SVGCore"],
    ),
    .target(
      name: "SVGRenderLayer",
      dependencies: ["SVGCore", "SVGRenderCG"],
    ),
    .target(
      name: "SVGUIView",
      dependencies: ["SVGCore", "SVGRenderCG"],
    ),
    .target(
      name: "SVGView",
      dependencies: ["SVGUIView"],
    ),
    .target(
      name: "_CSSParser"
    ),
    .target(
      name: "_SelectorParser",
      dependencies: ["_CSSParser"]
    ),
    .testTarget(
      name: "SVGCoreTests",
      dependencies: ["SVGCore", "_CSSParser", "_SelectorParser"],
    ),
    .testTarget(
      name: "SVGRenderLayerTests",
      dependencies: ["SVGRenderLayer", "SVGRenderCG", "SVGCore"],
    ),
    .testTarget(
      name: "SVGUIViewTests",
      dependencies: ["SVGUIView", "SVGCore"],
    ),
    .testTarget(
      name: "SVGViewTests",
      dependencies: ["SVGView"],
    ),
    .testTarget(
      name: "_CSSParserTests",
      dependencies: ["_CSSParser"],
      resources: [.process("assets")],
    ),
    .testTarget(
      name: "_SelectorParserTests",
      dependencies: ["_SelectorParser"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
