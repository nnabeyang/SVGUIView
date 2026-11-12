import CoreGraphics
import Foundation
import ImageIO

final class SVGImageElement: ShapeGeometry {
  static var type: SVGElementName {
    .image
  }

  var type: SVGElementName {
    .image
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
  /// The fragment of the `href`, which names a `<view>` of an SVG image that sets its view box, or `nil`.
  let fragment: String?
  let x: SVGLength?
  let y: SVGLength?
  /// The width, or `nil` where it's missing or `auto`, which the size of the image decides.
  let width: SVGLength?
  /// The height, or `nil` where it's missing or `auto`, which the size of the image decides.
  let height: SVGLength?
  /// How the image is placed in the rectangle of `x`, `y`, `width` and `height`.
  let preserveAspectRatio: PreserveAspectRatio

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    // An href can be a data URL of megabytes, which is read without copying it more than once.
    let href = EmbeddedImage.trimmed(attributes["href", default: ""])
    if href.isEmpty || href.hasPrefix("#") {
      source = nil
      fragment = nil
    } else if EmbeddedImage.isDataURL(href) {
      let url = EmbeddedImage.dataURL(ofHref: href)
      source = url.map { .data($0.data) }
      fragment = url?.fragment
    } else {
      source = .external(String(href))
      fragment = EmbeddedImage.fragment(ofHref: href)
    }
    // The position and the size are geometry properties, which style sheets set, and whose presentation attributes
    // are read as CSS.
    x = base.style.x
    y = base.style.y
    width = base.style.width
    height = base.style.height
    preserveAspectRatio =
      PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""]) ?? PreserveAspectRatio()
  }

  /// The rectangle of the element where its `width` and `height` are given. A `width` or a `height` of `auto` takes
  /// the size of the image, which ``RenderTreeBuilder/imageRect(of:context:)`` reads, and is 0 here.
  func path(in context: any GeometryContext) -> CGPath? {
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .height) ?? 0
    let width = width?.value(context: context, mode: .width) ?? 0
    let height = height?.value(context: context, mode: .height) ?? 0

    guard width > 0, height > 0 else {
      return nil
    }
    let path = CGPath(rect: .init(x: x, y: y, width: width, height: height), transform: nil)
    return path
  }
}
