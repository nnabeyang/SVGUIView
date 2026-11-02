import CoreGraphics
import Foundation

/// How `feComposite` combines its inputs, the value of its `operator`.
package enum SVGCompositeOperator: String, Sendable {
  case over
  case `in`
  case out
  case atop
  case xor
  case arithmetic
}

final class SVGFeCompositeElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feComposite
  }

  var type: SVGElementName {
    .feComposite
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  let input2: SVGFilterInput?
  /// The operator, which is `over` where the attribute is missing or isn't one of the operators.
  let compositeOperator: SVGCompositeOperator
  /// The coefficients of `arithmetic`, which are 0 where the attributes are missing or aren't numbers.
  let k1: Double
  let k2: Double
  let k3: Double
  let k4: Double

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
    compositeOperator = SVGCompositeOperator(rawValue: attributes["operator", default: ""]) ?? .over
    func number(_ name: String) -> Double {
      attributes[name].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
        ?? 0
    }
    k1 = number("k1")
    k2 = number("k2")
    k3 = number("k3")
    k4 = number("k4")
  }
}

extension SVGFeCompositeElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
