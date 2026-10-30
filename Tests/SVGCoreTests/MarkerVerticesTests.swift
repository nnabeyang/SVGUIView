import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

@Suite("Marker vertices")
struct MarkerVerticesTests {
  /// The points and the angles of the vertices of path data, as `[x, y, angle]`.
  private func vertices(_ d: String) -> [[Double]] {
    vertices(of: PathData(d))
  }

  private func vertices(of data: PathData) -> [[Double]] {
    MarkerVertices.vertices(of: data).map { [$0.point.x, $0.point.y, $0.angle] }
  }

  private func expectClose(
    _ actual: [[Double]], _ expected: [[Double]], sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let isClose =
      actual.count == expected.count
      && zip(actual, expected).allSatisfy { a, e in zip(a, e).allSatisfy { abs($0 - $1) < 0.001 } }
    #expect(isClose, "\(actual) isn't \(expected)", sourceLocation: sourceLocation)
  }

  @Test("the start of an open subpath takes the direction out of it, its end the direction into it, and the vertices between them the bisector")
  func openPath() {
    expectClose(vertices("M 0 0 L 10 0 L 10 10"), [[0, 0, 0], [10, 0, 45], [10, 10, 90]])
    expectClose(vertices("m 0 0 h 10 v 10"), [[0, 0, 0], [10, 0, 45], [10, 10, 90]])
  }

  @Test("both ends of a closed subpath take the bisector of the closing segment and the first one")
  func closedPath() {
    expectClose(
      vertices("M 0 0 L 10 0 L 10 10 Z"),
      [[0, 0, -67.5], [10, 0, 45], [10, 10, 157.5], [0, 0, -67.5]])
    // A closepath right after another adds no vertex.
    expectClose(vertices("M 0 0 L 10 0 L 10 10 Z Z"), vertices("M 0 0 L 10 0 L 10 10 Z"))
  }

  @Test("every subpath has vertices at its start and at the ends of its segments")
  func subpaths() {
    expectClose(vertices("M 0 0 L 10 0 M 0 10 L 10 10"), [[0, 0, 0], [10, 0, 0], [0, 10, 0], [10, 10, 0]])
  }

  @Test("a curve takes the directions to its first control point and from its last one")
  func curves() {
    expectClose(vertices("M 0 0 C 0 10 10 10 10 0"), [[0, 0, 90], [10, 0, -90]])
    // A control point at an end points to the next point.
    expectClose(vertices("M 0 0 C 0 0 10 10 10 0"), [[0, 0, 45], [10, 0, -90]])
    expectClose(vertices("M 0 0 Q 10 0 10 10"), [[0, 0, 0], [10, 10, 90]])
  }

  @Test("a segment of zero length takes the direction of the segment before it, or of the one after it")
  func zeroLength() {
    expectClose(vertices("M 0 0 L 0 0 L 10 0"), [[0, 0, 0], [0, 0, 0], [10, 0, 0]])
    expectClose(vertices("M 0 0 L 0 10 L 0 10"), [[0, 0, 90], [0, 10, 90], [0, 10, 90]])
    expectClose(vertices("M 5 5"), [[5, 5, 0]])
  }

  @Test("an arc takes the directions of its ellipse at its ends")
  func arc() {
    // Half a circle over its center from the left to the right, which starts up and ends down.
    expectClose(vertices("M 0 0 A 10 10 0 0 1 20 0"), [[0, 0, -90], [20, 0, 90]])
    expectClose(vertices("M 0 0 A 10 10 0 0 0 20 0"), [[0, 0, 90], [20, 0, -90]])
  }

  @Test("an ellipse and a rectangle have the vertices of their paths in SVG 2")
  func shapes() {
    expectClose(
      vertices(of: .ellipse(center: .zero, radii: CGSize(width: 10, height: 10))),
      [[10, 0, 90], [0, 10, 180], [-10, 0, -90], [0, -10, 0], [10, 0, 90], [10, 0, 90]])
    let points = SVGUIPoints(description: "0,0 10,0 10,5")
    expectClose(
      vertices(of: points.pathData(isClosed: false)!), [[0, 0, 0], [10, 0, 45], [10, 5, 90]])
  }

  @Test("the vertices take a transform, which turns their directions too")
  func transform() {
    let data = PathData("M 0 0 L 10 0")
    let vertices = MarkerVertices.vertices(of: data, transform: CGAffineTransform(scaleX: 1, y: -1).rotated(by: .pi / 2))
    #expect(vertices.map { abs($0.angle - -90) < 0.001 } == [true, true])
  }
}
