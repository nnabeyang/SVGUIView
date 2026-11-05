import CoreGraphics
import Foundation

/// The kind of matrix that `feColorMatrix` applies, the value of its `type`.
enum SVGColorMatrixType: String {
  case matrix
  case saturate
  case hueRotate
  case luminanceToAlpha
}

final class SVGFeColorMatrixElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feColorMatrix
  }

  var type: SVGElementName {
    .feColorMatrix
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  /// The kind of matrix, which is `matrix` where the attribute is missing or isn't one of the kinds.
  let matrixType: SVGColorMatrixType
  /// The numbers of `values`, or `nil` where the attribute is missing or isn't a list of numbers.
  let values: [Double]?

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    matrixType = SVGColorMatrixType(rawValue: attributes["type", default: ""]) ?? .matrix
    values = attributes["values"].flatMap(numberList)
  }
}
