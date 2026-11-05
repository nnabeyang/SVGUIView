import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

private func isClose(_ a: Double, _ b: Double, _ accuracy: Double = 1e-6) -> Bool {
  abs(a - b) < accuracy
}

@Suite("Path measure")
struct PathMeasureTests {
  /// Path data and its length.
  private static let lengths: [(String, Double)] = [
    ("M0 0 L30 40", 50),
    ("M0 0 H10 V10 Z", 10 + 10 + sqrt(200)),
    // A moveto in the middle jumps without adding to the length.
    ("M0 0 L10 0 M50 50 L50 60", 20),
    ("M5 5", 0),
    // A quarter of a circle of radius 100, as an elliptical arc.
    ("M100 0 A100 100 0 0 1 0 100", Double.pi * 50),
  ]

  @Test("the length of a path", arguments: lengths)
  func pathLengths(text: String, length: Double) {
    #expect(isClose(PathMeasure(PathData(text)).length, length, 0.05))
  }

  @Test("points along a path, with the angles that the path goes in")
  func points() throws {
    let measure = PathMeasure(PathData("M0 0 L10 0 L10 10"))
    let start = try #require(measure.point(atDistance: 0))
    #expect(start.point == CGPoint(x: 0, y: 0))
    #expect(isClose(start.angle, 0))
    let middle = try #require(measure.point(atDistance: 15))
    #expect(middle.point == CGPoint(x: 10, y: 5))
    #expect(isClose(middle.angle, 90))
    // A distance outside the path is clamped to it.
    #expect(measure.point(atDistance: 100)?.point == CGPoint(x: 10, y: 10))
    #expect(measure.point(atDistance: -5)?.point == CGPoint(x: 0, y: 0))
    #expect(PathMeasure(PathData("")).point(atDistance: 0) == nil)
    #expect(PathMeasure(PathData("M3 4")).point(atDistance: 0)?.point == CGPoint(x: 3, y: 4))
  }

  @Test("points on a path, which a distance outside the path has none of")
  func pointsOnPath() throws {
    let measure = PathMeasure(PathData("M0 0 L10 0 L10 10"))
    #expect(measure.point(onPathAt: 15)?.point == CGPoint(x: 10, y: 5))
    #expect(measure.point(onPathAt: 20)?.point == CGPoint(x: 10, y: 10))
    #expect(measure.point(onPathAt: 20.5) == nil)
    #expect(measure.point(onPathAt: -0.5) == nil)
    #expect(measure.end == CGPoint(x: 10, y: 10))
  }

  @Test("a path is closed if it's one subpath that ends with a closepath")
  func closed() {
    #expect(PathMeasure(PathData("M0 0 H10 V10 Z")).isClosed)
    #expect(PathMeasure(PathData("M0 0 H10 V10 Z")).end == CGPoint(x: 0, y: 0))
    #expect(!PathMeasure(PathData("M0 0 H10 V10")).isClosed)
    #expect(!PathMeasure(PathData("M0 0 H10 Z M20 0 H30 Z")).isClosed)
  }

  @Test("a reversed path goes from its end to its start")
  func reversedPath() throws {
    let measure = PathMeasure(PathData("M0 0 L10 0 M20 0 L20 10")).reversed()
    #expect(isClose(measure.length, 20))
    #expect(measure.start == CGPoint(x: 20, y: 10))
    #expect(measure.end == CGPoint(x: 0, y: 0))
    let first = try #require(measure.point(onPathAt: 5))
    #expect(first.point == CGPoint(x: 20, y: 5))
    #expect(isClose(first.angle, -90))
    #expect(measure.point(onPathAt: 15)?.point == CGPoint(x: 5, y: 0))
    #expect(PathMeasure(PathData("M0 0 H10 V10 Z")).reversed().isClosed)
  }

  @Test("a path is measured with its transform")
  func transformed() throws {
    let measure = PathMeasure(PathData("M0 0 L10 0"), transform: CGAffineTransform(scaleX: 2, y: 2).rotated(by: .pi / 2))
    #expect(isClose(measure.length, 20))
    let end = try #require(measure.point(onPathAt: 20))
    #expect(isClose(end.point.x, 0) && isClose(end.point.y, 20))
    #expect(isClose(end.angle, 90))
  }

  @Test("a moveto jumps to its point")
  func jumps() throws {
    let measure = PathMeasure(PathData("M0 0 L10 0 M50 50 L50 60"))
    #expect(measure.point(atDistance: 15)?.point == CGPoint(x: 50, y: 55))
  }

  @Test("the vertices are the ends of the commands")
  func vertices() {
    #expect(PathMeasure(PathData("M0 0 L10 0 L10 20 Z")).vertexDistances.map { $0.rounded() } == [0, 10, 30, 52])
    // An arc is one command, although it's drawn as curves.
    #expect(PathMeasure(PathData("M0 0 A10 10 0 0 1 0 20 L5 20")).vertexDistances.count == 3)
    #expect(PathMeasure(PathData("L5 5 M0 0 L3 4")).vertexDistances == [0, 5])
  }
}
