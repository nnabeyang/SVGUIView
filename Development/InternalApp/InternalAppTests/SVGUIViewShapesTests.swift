import Foundation
import SVGSnapshotAssets

final class SVGUIViewShapesTests: SVGUIViewBasicSnapshotsTests {
  func testCircle() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "circle"))
  }
}
