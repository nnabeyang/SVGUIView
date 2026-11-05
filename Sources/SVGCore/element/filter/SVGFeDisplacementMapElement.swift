import CoreGraphics
import Foundation

/// A component of the pixels of the map of `feDisplacementMap`, the value of its `xChannelSelector` or
/// `yChannelSelector`.
package enum SVGChannelSelector: String, Sendable {
  case red = "R"
  case green = "G"
  case blue = "B"
  case alpha = "A"
}

final class SVGFeDisplacementMapElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feDisplacementMap
  }

  var type: SVGElementName {
    .feDisplacementMap
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  /// The image that the primitive displaces.
  let input: SVGFilterInput?
  /// The map, whose components give the displacements.
  let input2: SVGFilterInput?
  /// The scale of the displacements, which is 0 where the attribute is missing or isn't a number.
  let scale: Double
  /// The components of the map for x and y, which are alpha where the attributes are missing or aren't components.
  let xChannelSelector: SVGChannelSelector
  let yChannelSelector: SVGChannelSelector

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    input2 = SVGFilterInput(rawValue: attributes["in2", default: ""])
    scale =
      attributes["scale"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
      ?? 0
    xChannelSelector = SVGChannelSelector(rawValue: attributes["xChannelSelector", default: ""]) ?? .alpha
    yChannelSelector = SVGChannelSelector(rawValue: attributes["yChannelSelector", default: ""]) ?? .alpha
  }
}
