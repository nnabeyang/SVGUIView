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
  /// How the image is placed in the rectangle of `x`, `y`, `width` and `height`.
  let preserveAspectRatio: PreserveAspectRatio

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    data = EmbeddedImage.data(ofHref: attributes["href", default: ""])
    x = SVGLength(attributes["x"]) ?? .pixel(0)
    y = SVGLength(attributes["y"]) ?? .pixel(0)
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    preserveAspectRatio =
      PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""]) ?? PreserveAspectRatio()
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
    return path
  }

  /// The image of the data, or `nil` if the data isn't an image.
  func decodedImage() -> CGImage? {
    data.flatMap(EmbeddedImage.decodedImage(of:))
  }

  /// The data of the SVG image that the data is, gzipped or not, or `nil` if it doesn't start like an XML document.
  func svgData() -> Data? {
    data.flatMap(EmbeddedImage.svgData(of:))
  }
}
