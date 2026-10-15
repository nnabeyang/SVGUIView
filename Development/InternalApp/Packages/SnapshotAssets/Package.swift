// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The binary targets are built by `scripts/publish.sh` in the
// nnabeyang/SnapshotAssets repository. Each one points at an asset of a
// release of that repository, tagged `test-suite/<version>` or
// `references/<version>`.
let package = Package(
  name: "SnapshotAssets",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "SVGSnapshotAssets", targets: ["SVGTestSuite", "SVGSnapshotReferences"])
  ],
  targets: [
    .binaryTarget(
      name: "SVGTestSuite",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/643612234.zip",
      checksum: "2473594258a96960626457408dbbde02d25606aadac5bc79beee123b42afddde"),
    .binaryTarget(
      name: "SVGSnapshotReferences",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/643703955.zip",
      checksum: "8f0193a0620d16bd4fe4066030b71908a59586c2cbbf2583d626f7f7a775308c"),
  ]
)
