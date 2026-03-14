import Foundation
import SVGSnapshotAssets

final class SVGUIViewStructureTests: SVGUIViewBasicSnapshotsTests {
  func testDefs() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "defs"))
  }

  func testG() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "g"))
  }

  func testImage() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "image"))
  }

  func testStyle() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "style"))
  }

  func testStyleAttribute() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "style-attribute"))
  }

  func testSvg() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "svg"))
  }

  func testTransform() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "transform"))
  }

  func testUse() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "structure", "use"))
  }
}
