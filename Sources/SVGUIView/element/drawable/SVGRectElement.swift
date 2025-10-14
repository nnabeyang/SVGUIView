import UIKit

struct SVGRectElement: SVGDrawableElement {
  var type: SVGElementName {
    .rect
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let rx: SVGLength?
  let ry: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    x = SVGLength(style: base.style[.x], value: attributes["x"])
    y = SVGLength(style: base.style[.y], value: attributes["y"])
    rx = .init(attributes["rx"])
    ry = .init(attributes["ry"])
    width = SVGLength(style: base.style[.width], value: attributes["width"])
    height = SVGLength(style: base.style[.height], value: attributes["height"])
  }

  init(other: Self, index: Int, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, index: index, css: css)
    x = SVGLength(style: css[.x], value: nil) ?? other.x
    y = SVGLength(style: css[.y], value: nil) ?? other.y
    rx = other.rx
    ry = other.ry
    width = SVGLength(style: css[.width], value: nil) ?? other.width
    height = SVGLength(style: css[.height], value: nil) ?? other.height
  }

  init(other: Self, attributes: [String: String]) {
    base = SVGBaseElement(other: other.base, attributes: attributes)
    x = other.x
    y = other.y
    rx = other.rx
    ry = other.ry
    width = other.width
    height = other.height
  }

  func toBezierPath(context: SVGContext) -> UIBezierPath? {
    color.map {
      context.push(color: $0)
    }
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .height) ?? 0
    let _rx = (rx?.value(context: context, mode: .width)).flatMap { $0 < 0 ? nil : $0 }
    let _ry = (ry?.value(context: context, mode: .height)).flatMap { $0 < 0 ? nil : $0 }
    let rx: CGFloat = _rx ?? _ry ?? 0
    let ry: CGFloat = _ry ?? _rx ?? 0
    let width = width?.value(context: context, mode: .width) ?? 0
    let height = height?.value(context: context, mode: .height) ?? 0
    guard width > 0, height > 0 else {
      return nil
    }
    let cornerSize = CGSize(width: min(width / 2.0, rx), height: min(height / 2.0, ry))
    let path = UIBezierPath(roundedRect: .init(x: x, y: y, width: width, height: height), cornerSize: cornerSize)
    path.apply(scale(context: context))
    return path
  }
}

extension SVGRectElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case x
    case y
    case width
    case height
    case fill
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
    try container.encode(fill, forKey: .fill)
  }
}
