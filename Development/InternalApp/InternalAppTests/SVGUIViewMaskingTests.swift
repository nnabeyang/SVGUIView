import Foundation
import SVGSnapshotAssets

final class SVGUIViewMaskingTests: SVGUIViewBasicSnapshotsTests {
  func testClipPath() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "masking", "clipPath"))
  }

  func testMask() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "masking", "mask"))
  }
}
