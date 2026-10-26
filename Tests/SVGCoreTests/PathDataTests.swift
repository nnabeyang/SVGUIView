import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

private func command(_ type: PathSegmentType, _ values: Double...) -> PathCommand {
  PathCommand(type: type, values: values)
}

@Suite("Path data")
struct PathDataTests {
  /// Path data and its commands.
  private static let paths: [(String, [PathCommand])] = [
    ("M 10 20 30 40 50 60", [command(.M, 10, 20), command(.L, 30, 40), command(.L, 50, 60)]),
    ("m10,20 30,40", [command(.m, 10, 20), command(.l, 30, 40)]),
    (
      "M0 0H10V20h-5v-5z",
      [command(.M, 0, 0), command(.H, 10), command(.V, 20), command(.h, -5), command(.v, -5), command(.z)]
    ),
    ("M0 0C1 2 3 4 5 6S7 8 9 10", [command(.M, 0, 0), command(.C, 1, 2, 3, 4, 5, 6), command(.S, 7, 8, 9, 10)]),
    ("M0 0Q1 2 3 4T5 6 7 8", [command(.M, 0, 0), command(.Q, 1, 2, 3, 4), command(.T, 5, 6), command(.T, 7, 8)]),
    (
      "M0 0A10 20 30 1 0 40 50a1 1 0 0110 10",
      [
        command(.M, 0, 0), command(.A, 10, 20, 30, 1, 0, 40, 50), command(.a, 1, 1, 0, 0, 1, 10, 10),
      ]
    ),
    // Numbers without separators.
    ("M10-5L.5.5", [command(.M, 10, -5), command(.L, 0.5, 0.5)]),
    // An error stops the data, and the complete groups before it stay.
    ("M0 0L10 10 20", [command(.M, 0, 0), command(.L, 10, 10)]),
    ("M0 0L10 10X20 20", [command(.M, 0, 0), command(.L, 10, 10)]),
    ("M0 0L", [command(.M, 0, 0)]),
    ("M0 0A1 1 0 2 0 5 5", [command(.M, 0, 0)]),
    ("", []),
  ]

  @Test("path data is read as commands with one group of numbers each", arguments: paths)
  func commands(text: String, commands: [PathCommand]) {
    #expect(PathData(text) == PathData(commands: commands))
  }

  /// Path data, and points that its path ends at or passes.
  private static let shapes: [(String, CGPoint, CGRect)] = [
    ("M10 10 l10 0 0 10 z", CGPoint(x: 10, y: 10), CGRect(x: 10, y: 10, width: 10, height: 10)),
    ("M0 0 H10 V5 h-10", CGPoint(x: 0, y: 5), CGRect(x: 0, y: 0, width: 10, height: 5)),
    ("M0 0 C0 10 10 10 10 0 S20 -10 20 0", CGPoint(x: 20, y: 0), CGRect(x: 0, y: -7.5, width: 20, height: 15)),
    // Commands before the first moveto draw nothing.
    ("L5 5 M1 1 L2 2", CGPoint(x: 2, y: 2), CGRect(x: 1, y: 1, width: 1, height: 1)),
  ]

  @Test("the path of path data ends where its commands end", arguments: shapes)
  func shape(text: String, end: CGPoint, bounds: CGRect) throws {
    let context = SVGPathContext()
    for command in PathData(text).commands {
      context.apply(command)
    }
    let path = try #require(context.path)
    #expect(path.currentPoint == end)
    let box = path.boundingBoxOfPath
    #expect(abs(box.minX - bounds.minX) < 1e-9 && abs(box.minY - bounds.minY) < 1e-9, "\(box)")
    #expect(abs(box.width - bounds.width) < 1e-9 && abs(box.height - bounds.height) < 1e-9, "\(box)")
  }
}
