import UIKit

struct SVGEllipseElement: SVGDrawableElement {
  var type: SVGElementName {
    .ellipse
  }

  let base: SVGBaseElement
  let cx: SVGLength?
  let cy: SVGLength?
  let rx: SVGLength?
  let ry: SVGLength?

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    cx = SVGLength(attributes["cx"])
    cy = SVGLength(attributes["cy"])
    rx = SVGLength(attributes["rx"])
    ry = SVGLength(attributes["ry"])
  }

  init(other: Self, index: Int, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, index: index, css: css)
    cx = other.cx
    cy = other.cy
    rx = other.rx
    ry = other.ry
  }

  func toBezierPath(context: SVGContext) -> UIBezierPath? {
    let cx = cx?.value(context: context, mode: .width) ?? 0
    let cy = cy?.value(context: context, mode: .height) ?? 0
    let _rx = (rx?.value(context: context, mode: .width)).flatMap { $0 < 0 ? nil : $0 }
    let _ry = (ry?.value(context: context, mode: .height)).flatMap { $0 < 0 ? nil : $0 }
    let rx: CGFloat = _rx ?? _ry ?? 0
    let ry: CGFloat = _ry ?? _rx ?? 0
    guard rx > 0, ry > 0 else { return nil }
    let path = UIBezierPath(ovalIn: CGRect(origin: CGPoint(x: cx - rx, y: cy - ry), size: CGSize(width: 2 * rx, height: 2 * ry)))
    path.apply(scale(context: context))
    return path
  }
}

extension SVGEllipseElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case cx
    case cy
    case rx
    case ry
    case fill
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(cx, forKey: .cx)
    try container.encode(cy, forKey: .cy)
    try container.encode(rx, forKey: .rx)
    try container.encode(ry, forKey: .ry)
    try container.encode(fill, forKey: .fill)
  }
}
