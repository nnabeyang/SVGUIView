import CoreGraphics
import Foundation

final class SVGRectElement: ShapeGeometry {
  static var type: SVGElementName {
    .rect
  }

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
    x = base.style.x
    y = base.style.y
    rx = .init(attributes["rx"])
    ry = .init(attributes["ry"])
    width = base.style.width
    height = base.style.height
  }

  func path(in context: any GeometryContext) -> CGPath? {
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
    let path = CGMutablePath()
    path.addRoundedRect(.init(x: x, y: y, width: width, height: height), cornerSize: cornerSize)
    return path.applying(scale(context: context))
  }
}

extension SVGRectElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case x
    case y
    case width
    case height
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
  }
}
