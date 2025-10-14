import UIKit

struct SVGPolylineElement: SVGDrawableElement {
  var type: SVGElementName {
    .polyline
  }

  let base: SVGBaseElement
  let points: SVGUIPoints

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    points = .init(description: attributes["points", default: ""])
  }

  init(other: Self, index: Int, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, index: index, css: css)
    points = other.points
  }

  func toBezierPath(context: SVGContext) -> UIBezierPath? {
    points.polyline.map {
      $0.apply(scale(context: context))
      return $0
    }
  }
}

extension SVGPolylineElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case points
    case fill
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(points, forKey: .points)
    try container.encode(fill, forKey: .fill)
  }
}
