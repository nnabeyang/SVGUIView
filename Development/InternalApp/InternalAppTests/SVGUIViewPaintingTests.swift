import Foundation
import SVGSnapshotAssets

final class SVGUIViewPaintingTests: SVGUIViewBasicSnapshotsTests {
  func testFill() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "painting", "fill"))
  }

  func testFillOpacity() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "painting", "fill-opacity"))
  }
}
