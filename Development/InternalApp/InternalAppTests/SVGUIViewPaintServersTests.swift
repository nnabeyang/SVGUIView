import Foundation
import SVGSnapshotAssets

final class SVGUIViewPaintServersTests: SVGUIViewBasicSnapshotsTests {
  func testLinearGradient() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "paint-servers", "linearGradient"))
  }

  func testPattern() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "paint-servers", "pattern"))
  }

  func testRadialGradient() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "paint-servers", "radialGradient"))
  }

}
