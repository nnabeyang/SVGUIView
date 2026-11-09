import CoreGraphics
import Foundation

final class SVGFeImageElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feImage
  }

  var type: SVGElementName {
    .feImage
  }

  /// What the primitive draws, from its `href`.
  enum Source {
    /// The element of an ID in the document.
    case element(String)
    /// The data of a data URL.
    case data(Data)
    /// A file that an `href` references, which a rendering reads if its loader allows it.
    case external(String)
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  /// What the primitive draws, or `nil` where `href` is missing, or is a reference to an element that isn't an ID or
  /// a data URL that isn't base64.
  let source: Source?
  /// How an image is placed in the subregion.
  let preserveAspectRatio: PreserveAspectRatio

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    let href = attributes["href", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    if href.isEmpty {
      source = nil
    } else if href.hasPrefix("#") {
      source = fragmentID(of: href).map { .element($0) }
    } else if href.lowercased().hasPrefix("data:") {
      source = EmbeddedImage.data(ofHref: href).map { .data($0) }
    } else {
      source = .external(href)
    }
    preserveAspectRatio =
      PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""]) ?? PreserveAspectRatio()
  }
}
