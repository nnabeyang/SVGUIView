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
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  /// What the primitive draws, or `nil` where `href` is missing or isn't a reference to an element or a data URL in
  /// base64. Other URLs, such as the files beside the document, aren't read.
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

    let href = attributes["href", default: ""].trimmingCharacters(in: .whitespaces)
    if href.hasPrefix("#") {
      source = .element(String(href.dropFirst()))
    } else if href.lowercased().hasPrefix("data:") {
      source = EmbeddedImage.data(ofHref: href).map { .data($0) }
    } else {
      source = nil
    }
    preserveAspectRatio =
      PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""]) ?? PreserveAspectRatio()
  }
}

extension SVGFeImageElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
