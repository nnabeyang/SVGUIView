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
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/374092343.zip",
      checksum: "ee9a0a9ffadd9aa844b48846dc046b72f46e070e791ae77be4e720e0235e996e")
  ]
)
