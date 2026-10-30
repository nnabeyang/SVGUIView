import CoreGraphics
import Foundation

final class SVGPolylineElement: ShapeGeometry {
  static var type: SVGElementName {
    .polyline
  }

  var type: SVGElementName {
    .polyline
  }

  let base: SVGBaseElement
  let points: SVGUIPoints

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    points = .init(description: attributes["points", default: ""])
  }

  func path(in context: any GeometryContext) -> CGPath? {
    points.polyline?.applying(scale(context: context))
  }

  func markerPath(in _: any GeometryContext) -> PathData? {
    points.pathData(isClosed: false)
  }
}

extension SVGPolylineElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case points
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(points, forKey: .points)
  }
}
