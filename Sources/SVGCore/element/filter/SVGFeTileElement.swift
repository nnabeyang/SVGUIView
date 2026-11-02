import CoreGraphics
import Foundation

final class SVGFeTileElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feTile
  }

  var type: SVGElementName {
    .feTile
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
  }
}

extension SVGFeTileElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
