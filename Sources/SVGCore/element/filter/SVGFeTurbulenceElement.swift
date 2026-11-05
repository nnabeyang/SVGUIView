import CoreGraphics
import Foundation

/// Whether `feTurbulence` makes fractal noise or turbulence, the value of its `type`.
package enum SVGTurbulenceType: String, Sendable {
  case fractalNoise
  case turbulence
}

final class SVGFeTurbulenceElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feTurbulence
  }

  var type: SVGElementName {
    .feTurbulence
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  /// The type, which is `turbulence` where the attribute is missing or isn't one of the types.
  let turbulenceType: SVGTurbulenceType
  /// The base frequencies in x and y, which are both 0 where the attribute is missing or isn't one or two numbers.
  let baseFrequency: CGSize
  /// The number of octaves, which is 1 where the attribute is missing or isn't an integer.
  let numOctaves: Int
  /// The seed, which is 0 where the attribute is missing or isn't a number.
  let seed: Double
  /// Whether the noise stitches at the edges of the subregion, which it doesn't where the attribute is missing or
  /// isn't `stitch`.
  let stitchTiles: Bool

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    turbulenceType = SVGTurbulenceType(rawValue: attributes["type", default: ""]) ?? .turbulence
    let numbers = attributes["baseFrequency"].flatMap(numberList) ?? []
    baseFrequency =
      switch numbers.count {
      case 1: CGSize(width: numbers[0], height: numbers[0])
      case 2: CGSize(width: numbers[0], height: numbers[1])
      default: .zero
      }
    numOctaves = attributes["numOctaves"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1
    seed =
      attributes["seed"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
      ?? 0
    stitchTiles = attributes["stitchTiles"] == "stitch"
  }
}
