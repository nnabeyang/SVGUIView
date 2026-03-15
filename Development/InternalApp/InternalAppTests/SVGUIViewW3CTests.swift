import Foundation
import SVGSnapshotAssets

final class SVGUIViewW3CTests: SVGUIViewBasicSnapshotsTests {
  func testSVG_1_1F2() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "1.1F2"))
  }
}
