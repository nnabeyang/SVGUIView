import Foundation
import SVGSnapshotAssets

final class SVGUIViewShapesTests: SVGUIViewBasicSnapshotsTests {
  func testCircle() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "circle"))
  }

  func testEllipse() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "ellipse"))
  }

  func testLine() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "line"))
  }

  func testPath() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "path"))
  }

  func testPolygon() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "polygon"))
  }

  func testPolyline() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "polyline"))
  }

  func testRect() throws {
    try testBase(root: SnapshotAssets.bundle.bundleURL.appending(components: "Resources", "w3c", "basic", "shapes", "rect"))
  }
}
