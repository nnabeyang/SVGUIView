import Foundation
import SVGSnapshotAssets

final class SVGUIViewTextTests: SVGUIViewBasicSnapshotsTests {
  func testText() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "text", "text"))
  }

  func testFontWeight() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "text", "font-weight"))
  }

  func testFontFamily() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "text", "font-family"))
  }

  func testFontSize() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "text", "font-size"))
  }
}
