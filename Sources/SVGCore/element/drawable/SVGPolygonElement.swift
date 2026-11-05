import CoreGraphics
import Foundation

final class SVGPolygonElement: ShapeGeometry {
  static var type: SVGElementName {
    .polygon
  }

  var type: SVGElementName {
    .polygon
  }

  let base: SVGBaseElement
  let points: SVGUIPoints

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    points = .init(description: attributes["points", default: ""])
  }

  func path(in _: any GeometryContext) -> CGPath? {
    points.polygon
  }

  func markerPath(in _: any GeometryContext) -> PathData? {
    points.pathData(isClosed: true)
  }
}
