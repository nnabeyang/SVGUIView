import UIKit

final class SVGCircleElement: SVGDrawableElement {
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

  init(other: SVGCircleElement, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, css: css)
    cx = other.cx
    cy = other.cy
    r = other.r
  }

  init(other: SVGCircleElement, attributes: [String: String]) {
    base = SVGBaseElement(other: other.base, attributes: attributes)
    cx = other.cx
    cy = other.cy
    r = other.r
  }

  func toBezierPath(context: SVGContext) -> UIBezierPath? {
    let cx = cx?.value(context: context, mode: .width) ?? 0
    let cy = cy?.value(context: context, mode: .height) ?? 0
    let r = r?.value(context: context, mode: .other) ?? 0
    guard r > 0 else { return nil }
    let path = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: CGFloat(Double.pi) * 2, clockwise: true)
    path.apply(scale(context: context))
    return path
  }
}

extension SVGCircleElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case cx
    case cy
    case r
    case fill
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(cx, forKey: .cx)
    try container.encode(cy, forKey: .cy)
    try container.encode(r, forKey: .r)
    try container.encode(fill, forKey: .fill)
  }
}
