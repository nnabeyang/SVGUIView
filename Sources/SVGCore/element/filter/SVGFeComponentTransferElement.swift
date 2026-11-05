import CoreGraphics
import Foundation

final class SVGFeComponentTransferElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feComponentTransfer
  }

  var type: SVGElementName {
    .feComponentTransfer
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
  }
}

/// The kind of transfer function of a `feFuncR`, `feFuncG`, `feFuncB` or `feFuncA`, the value of its `type`.
enum SVGTransferFunctionType: String {
  case identity
  case table
  case discrete
  case linear
  case gamma
}

/// A `feFuncR`, `feFuncG`, `feFuncB` or `feFuncA`, the transfer function of a component in a `feComponentTransfer`.
final class SVGFeFuncElement: SVGElement {
  static var type: SVGElementName {
    .feFuncR
  }

  /// The name of the element, which tells the component.
  var type: SVGElementName {
    base.name
  }

  let base: SVGBaseElement
  /// The kind of function, or `nil` where the attribute is missing or isn't one of the kinds.
  let functionType: SVGTransferFunctionType?
  /// The numbers of `tableValues`, or `nil` where the attribute is missing or isn't a list of numbers.
  let tableValues: [Double]?
  let slope: Double?
  let intercept: Double?
  let amplitude: Double?
  let exponent: Double?
  let offset: Double?

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    functionType = attributes["type"].flatMap(SVGTransferFunctionType.init(rawValue:))
    tableValues = attributes["tableValues"].flatMap(numberList)
    func number(_ name: String) -> Double? {
      attributes[name].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
    }
    slope = number("slope")
    intercept = number("intercept")
    amplitude = number("amplitude")
    exponent = number("exponent")
    offset = number("offset")
  }
}
