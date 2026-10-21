import CoreGraphics
import Foundation
import ImageIO

final class SVGImageElement: ShapeGeometry {
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

  func toPath(context: SVGContext) -> CGPath? {
    path(in: context)
  }

  func path(in context: any GeometryContext) -> CGPath? {
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .width) ?? 0
    let width = width?.value(context: context, mode: .width) ?? 0
    let height = height?.value(context: context, mode: .height) ?? 0

    guard width > 0, height > 0 else {
      return nil
    }
    let path = CGPath(rect: .init(x: x, y: y, width: width, height: height), transform: nil)
    return path.applying(scale(context: context))
  }

  /// The image of the data, or `nil` if the data isn't an image.
  func decodedImage() -> CGImage? {
    guard let data = data,
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

extension SVGImageElement: Encodable {
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
