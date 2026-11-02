import CoreGraphics
import Foundation

final class SVGFeDropShadowElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feDropShadow
  }

  var type: SVGElementName {
    .feDropShadow
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  /// The offset of the shadow, or `nil` where the attribute is missing or isn't a number.
  let dx: Double?
  let dy: Double?
  let stdDeviation: StdDeviation?

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

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    dx = Double(attributes["dx", default: ""])
    dy = Double(attributes["dy", default: ""])
    stdDeviation = StdDeviation(description: attributes["stdDeviation", default: ""])

    floodColor = base.style.resolved(base.style.floodColor)
    floodOpacity = base.style.floodOpacity
  }
}

extension SVGFeDropShadowElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
