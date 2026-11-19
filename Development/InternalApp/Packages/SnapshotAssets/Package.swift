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
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/766119253.zip",
      checksum: "3bb9d9f995dd36e0efd8d8e0520f845c7aff1e42752e46ea7c0ce211f7eef50d"),
    .binaryTarget(
      name: "SVGSnapshotReferences",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/766120681.zip",
      checksum: "b51cb6b72be144fa7c353d80ade003516dc3d57b87aa95d4e35df105a98d8413"),
  ]
)
