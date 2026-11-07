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
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/722058022.zip",
      checksum: "f9969839dc680dbb6f48207891a0ab8dad5929fedded3413d73e796a4e2af0b8"),
    .binaryTarget(
      name: "SVGSnapshotReferences",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/720630468.zip",
      checksum: "3544591d478fa3d24e3ba0740bcff8f821916f3e1bd5fb353b0b5f0c7b192284"),
  ]
)
