import CoreGraphics
import Foundation

/// Whether `feMorphology` thins or fattens its input, the value of its `operator`.
package enum SVGMorphologyOperator: String, Sendable {
  case erode
  case dilate
}

final class SVGFeMorphologyElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feMorphology
  }

  var type: SVGElementName {
    .feMorphology
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  /// The operator, which is `erode` where the attribute is missing or isn't one of the operators.
  let morphologyOperator: SVGMorphologyOperator
  /// The radii in x and y, which are both 0 where the attribute is missing or isn't one or two numbers.
  let radius: CGSize

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    morphologyOperator = SVGMorphologyOperator(rawValue: attributes["operator", default: ""]) ?? .erode
    let numbers = attributes["radius"].flatMap(numberList) ?? []
    radius =
      switch numbers.count {
      case 1: CGSize(width: numbers[0], height: numbers[0])
      case 2: CGSize(width: numbers[0], height: numbers[1])
      default: .zero
      }
  }
}

extension SVGFeMorphologyElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
