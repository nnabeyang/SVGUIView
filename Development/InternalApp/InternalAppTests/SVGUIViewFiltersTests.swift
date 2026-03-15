import Foundation
import SVGSnapshotAssets

final class SVGUIViewFiltersTests: SVGUIViewBasicSnapshotsTests {
  func testFeBlend() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "filters", "feBlend"))
  }

  func testFeFlood() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "filters", "feFlood"))
  }

  func testFeGaussianBlur() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "filters", "feGaussianBlur"))
  }

  func testFeMerge() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "filters", "feMerge"))
  }

  func testFeOffset() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "filters", "feOffset"))
  }

  func testFilter() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "filters", "filter"))
  }
}
