import CoreGraphics
import Foundation

final class SVGCircleElement: ShapeGeometry {
  static var type: SVGElementName {
    .circle
  }

  var type: SVGElementName {
    .circle
  }

  let base: SVGBaseElement
  let cx: SVGLength?
  let cy: SVGLength?
  let r: SVGLength?

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    cx = .init(attributes["cx"])
    cy = .init(attributes["cy"])
    r = .init(attributes["r"])
  }

  func markerPath(in context: any GeometryContext) -> PathData? {
    let r = r?.value(context: context, mode: .other) ?? 0
    guard r > 0 else { return nil }
    return .ellipse(
      center: CGPoint(x: cx?.value(context: context, mode: .width) ?? 0, y: cy?.value(context: context, mode: .height) ?? 0),
      radii: CGSize(width: r, height: r))
  }

  func path(in context: any GeometryContext) -> CGPath? {
    let cx = cx?.value(context: context, mode: .width) ?? 0
    let cy = cy?.value(context: context, mode: .height) ?? 0
    let r = r?.value(context: context, mode: .other) ?? 0
    guard r > 0 else { return nil }
    let path = CGMutablePath()
    // Core Graphics names directions in a coordinate space whose y-axis points up, so this is the clockwise
    // circle of UIKit.
    path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: CGFloat(Double.pi) * 2, clockwise: false)
    return path.applying(scale(context: context))
  }
}

extension SVGCircleElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case cx
    case cy
    case r
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(cx, forKey: .cx)
    try container.encode(cy, forKey: .cy)
    try container.encode(r, forKey: .r)
  }
}
