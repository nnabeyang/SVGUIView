import CoreGraphics
import Foundation

struct SVGUIPoints: Encodable {
  let points: [CGPoint]

  init(description: String) {
    var data = description
    let points = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanPoints()
    }
    self.points = points
  }

  var polygon: CGPath? {
    guard let path = mutablePolyline else { return nil }
    path.closeSubpath()
    return path
  }

  var polyline: CGPath? {
    mutablePolyline
  }

  /// The path data of the points, as a polyline or a polygon, or `nil` with fewer than two points.
  func pathData(isClosed: Bool) -> PathData? {
    guard points.count >= 2 else { return nil }
    let commands = points.enumerated().map { index, point in
      PathCommand(type: index == 0 ? .M : .L, values: [point.x, point.y])
    }
    return PathData(commands: commands + (isClosed ? [PathCommand(type: .Z, values: [])] : []))
  }

  private var mutablePolyline: CGMutablePath? {
    guard points.count >= 2, let first = points.first else { return nil }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: first.x, y: first.y))
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    return path
  }
}
