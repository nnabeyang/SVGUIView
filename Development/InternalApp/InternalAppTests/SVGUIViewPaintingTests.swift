import Foundation
import SVGTestSuite

final class SVGUIViewPaintingTests: SVGUIViewBasicSnapshotsTests {
  func testFill() throws {
    try testBase(root: TestSuite.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "painting", "fill"))
  }

  func testFillOpacity() throws {
    try testBase(root: TestSuite.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "painting", "fill-opacity"))
  }
}
