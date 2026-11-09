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

  /// Where the data of an image is.
  enum Source: Equatable {
    /// The data of a data URL.
    case data(Data)
    /// A file that an `href` references, which a rendering reads if its loader allows it.
    case external(String)
  }

  let base: SVGBaseElement
  /// Where the data of the image is, or `nil` where `href` is missing or is a data URL that isn't base64.
  let source: Source?
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  /// How the image is placed in the rectangle of `x`, `y`, `width` and `height`.
  let preserveAspectRatio: PreserveAspectRatio

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    let href = attributes["href", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    if href.isEmpty || href.hasPrefix("#") {
      source = nil
    } else if href.lowercased().hasPrefix("data:") {
      source = EmbeddedImage.data(ofHref: href).map { .data($0) }
    } else {
      source = .external(href)
    }
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
}
