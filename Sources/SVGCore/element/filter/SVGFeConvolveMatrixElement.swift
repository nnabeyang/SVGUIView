import CoreGraphics
import Foundation

/// How `feConvolveMatrix` extends its input past its edges, the value of its `edgeMode`.
package enum SVGEdgeMode: String, Sendable {
  case duplicate
  case wrap
  case none
}

final class SVGFeConvolveMatrixElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feConvolveMatrix
  }

  var type: SVGElementName {
    .feConvolveMatrix
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  /// The numbers of columns and rows, truncated towards 0, which are 3 where the attribute is missing or isn't one or
  /// two numbers.
  let order: (columns: Int, rows: Int)
  /// The kernel, row by row, which is empty where the attribute is missing or isn't numbers.
  let kernelMatrix: [Double]
  /// The divisor, which is `nil` where the attribute is missing or isn't a number.
  let divisor: Double?
  /// The bias, which is 0 where the attribute is missing or isn't a number.
  let bias: Double
  /// The column and the row of the kernel over each pixel, which are `nil` where the attributes are missing or
  /// aren't integers.
  let targetX: Int?
  let targetY: Int?
  /// How the input extends past its edges, which is `duplicate` where the attribute is missing or isn't a mode.
  let edgeMode: SVGEdgeMode
  /// Whether the kernel applies only to the colors, which it doesn't unless the attribute is `true`.
  let preserveAlpha: Bool

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    // Orders that aren't integers are truncated towards 0, and ones out of the range of integers are left as 0.
    let orders = (attributes["order"].flatMap(numberList) ?? []).map {
      abs($0) < 0x1p31 ? Int($0.rounded(.towardZero)) : 0
    }
    order =
      switch orders.count {
      case 1: (orders[0], orders[0])
      case 2: (orders[0], orders[1])
      default: (3, 3)
      }
    kernelMatrix = attributes["kernelMatrix"].flatMap(numberList) ?? []
    func number(_ name: String) -> Double? {
      attributes[name].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
    }
    divisor = number("divisor")
    bias = number("bias") ?? 0
    targetX = attributes["targetX"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    targetY = attributes["targetY"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    edgeMode = SVGEdgeMode(rawValue: attributes["edgeMode", default: ""]) ?? .duplicate
    preserveAlpha = attributes["preserveAlpha"] == "true"
  }
}

extension SVGFeConvolveMatrixElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
