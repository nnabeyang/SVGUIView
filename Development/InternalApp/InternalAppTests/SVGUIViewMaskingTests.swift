import Foundation
import SVGTestSuite

final class SVGUIViewMaskingTests: SVGUIViewBasicSnapshotsTests {
  func testClipPath() throws {
    try testBase(root: TestSuite.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "masking", "clipPath"))
  }

  func testMask() throws {
    try testBase(root: TestSuite.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "masking", "mask"))
  }
}
