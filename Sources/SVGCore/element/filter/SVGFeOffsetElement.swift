import CoreGraphics
import Foundation

final class SVGFeOffsetElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feOffset
  }

  var type: SVGElementName {
    .feOffset
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let dx: Double?
  let dy: Double?

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    dx = Double(attributes["dx", default: ""])
    dy = Double(attributes["dy", default: ""])
  }

}

extension SVGFeOffsetElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
