// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The binary targets are built by `scripts/publish.sh` in the
// nnabeyang/SnapshotAssets repository. Each one points at an asset of a
// release of that repository, tagged `test-suite/<version>` or
// `references/<version>`.
let package = Package(
  name: "SnapshotAssets",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "SVGSnapshotAssets", targets: ["SVGTestSuite", "SVGSnapshotReferences"])
  ],
  targets: [
    .binaryTarget(
      name: "SVGTestSuite",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/739777642.zip",
      checksum: "82e2dff85237ab153e5d3cbad804c7b37007cd498838ffbaa2fc6fbd5a707151"),
    .binaryTarget(
      name: "SVGSnapshotReferences",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/739779514.zip",
      checksum: "ce8d3518f166e9136147fb44b2de1a4577a4515be38057a045c7c5e14a32f011"),
  ]
)
