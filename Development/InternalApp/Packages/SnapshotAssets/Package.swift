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
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/802398177.zip",
      checksum: "6b28d4edc775525646c761d87dfc4ed5f51c0e900a697025058f74311021ecd6"),
    .binaryTarget(
      name: "SVGSnapshotReferences",
      url: "https://api.github.com/repos/nnabeyang/SnapshotAssets/releases/assets/802399374.zip",
      checksum: "bd6ce5f1122ed77f31f64796302fa26bb24483dcaec85cce2ef564e5a95003bb"),
  ]
)
