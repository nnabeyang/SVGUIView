import CoreGraphics
import Foundation
import ImageIO

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

  func toPath(context: SVGContext) -> CGPath? {
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

  /// Draws the image in the element's rectangle. The pixels are drawn as they're stored, without the orientation in
  /// the image's metadata, as `UIImage.cgImage` gives them.
  func applyFill(path: CGPath, context: SVGContext, mode _: DrawMode) async {
    guard let data = data,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return }
    let cgContext = context.graphics
    let bounds = path.boundingBoxOfPath
    let imageWidth = CGFloat(cgImage.width)
    let imageHeight = CGFloat(cgImage.height)
    let scale = scale(width: bounds.width, height: bounds.height, imageSize: .init(width: imageWidth, height: imageHeight))
    let frame = CGRect(origin: bounds.origin, size: .init(width: imageWidth * scale, height: imageHeight * scale))
    cgContext.scaleBy(x: 1, y: -1)
    cgContext.draw(cgImage, in: CGRect(x: frame.minX, y: -frame.height - frame.minY, width: frame.width, height: frame.height))
  }

  private func scale(width: CGFloat, height: CGFloat, imageSize size: CGSize) -> CGFloat {
    let sx = width / size.width
    let sy = height / size.height
    if width == 0 { return sy }
    if height == 0 { return sx }
    return width > height ? sy : sx
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
