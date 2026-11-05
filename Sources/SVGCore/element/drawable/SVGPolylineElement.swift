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

  func path(in _: any GeometryContext) -> CGPath? {
    points.polyline
  }

  func markerPath(in _: any GeometryContext) -> PathData? {
    points.pathData(isClosed: false)
  }
}
