import UIKit

final class SVGImageElement: SVGDrawableElement {
  static var type: SVGElementName {
    .circle
  }

  var type: SVGElementName {
    .circle
  }

  let base: SVGBaseElement
  let data: Data?
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    let src = attributes["href", default: ""].split(separator: ",").map { String($0) }
    data = src.last.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
    x = SVGLength(attributes["x"]) ?? .pixel(0)
    y = SVGLength(attributes["y"]) ?? .pixel(0)
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
  }

  init(other: SVGImageElement, css: SVGUIStyle) {
    base = SVGBaseElement(other: other.base, css: css)
    data = other.data
    x = other.x
    y = other.y
    width = other.width
    height = other.height
  }

  func toBezierPath(context: SVGContext) -> UIBezierPath? {
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .width) ?? 0
    let width = width?.value(context: context, mode: .width) ?? 0
    let height = height?.value(context: context, mode: .height) ?? 0

    guard width > 0, height > 0 else {
      return nil
    }
    let path = UIBezierPath(rect: .init(x: x, y: y, width: width, height: height))
    path.apply(scale(context: context))
    return path
  }

  var fill: SVGFill? {
    .image(data: data)
  }
}

extension SVGImageElement: Encodable {
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
