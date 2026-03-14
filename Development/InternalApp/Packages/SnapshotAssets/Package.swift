// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SnapshotAssets",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "SVGSnapshotAssets", targets: ["SVGSnapshotAssets"])
  ],
  targets: [
    .binaryTarget(
      name: "SVGSnapshotAssets",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/373595576.zip",
      checksum: "b0a273c30edc1a88d5dd3351372e72c5654990f92e3df19f56dd88c08f196d15")
  ]
)
