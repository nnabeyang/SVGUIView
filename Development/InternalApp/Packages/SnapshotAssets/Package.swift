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
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/374940855.zip",
      checksum: "27807086d48d351da3dcf1b65ff90b32a5a57c1d7a4f74aefec9534018d889f2")
  ]
)
