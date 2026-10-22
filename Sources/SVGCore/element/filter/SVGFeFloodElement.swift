import CoreGraphics
import Foundation

final class SVGFeFloodElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feFlood
  }

  var type: SVGElementName {
    .feFlood
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let floodColor: SVGColor
  let floodOpacity: Double

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    floodColor = base.style.resolved(base.style.floodColor)
    floodOpacity = base.style.floodOpacity
  }

}

extension SVGFeFloodElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
