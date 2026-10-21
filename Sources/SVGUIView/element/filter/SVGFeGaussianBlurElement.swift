import CoreGraphics
import Foundation

enum StdDeviation: Equatable {
  case iso(SVGLength)
  case hetero(x: SVGLength, y: SVGLength)
  init?(description: String) {
    var data = description
    let stdDeviation = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanStdDeviation()
    }
    guard let stdDeviation = stdDeviation else {
      return nil
    }
    self = stdDeviation
  }
}

extension StdDeviation: Encodable {
  private enum CodingKeys: String, CodingKey {
    case x
    case y
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    switch self {
    case .iso(let x):
      try container.encode(x, forKey: .x)
    case .hetero(let x, let y):
      try container.encode(x, forKey: .x)
      try container.encode(y, forKey: .y)
    }
  }
}

extension StdDeviation {
  static let zero: StdDeviation = .hetero(x: SVGLength(value: 0, unit: .number), y: SVGLength(value: 0, unit: .number))
}

enum SVGFilterInput {
  case sourceGraphic
  case sourceAlpha
  case other(String)

  init?(rawValue: String) {
    guard !rawValue.isEmpty else { return nil }
    switch rawValue {
    case "SourceGraphic":
      self = .sourceGraphic
    case "SourceAlpha":
      self = .sourceAlpha
    default:
      self = .other(rawValue)
    }
  }
}

final class SVGFeGaussianBlurElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feGaussianBlur
  }

  var type: SVGElementName {
    .feGaussianBlur
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?

  let colorInterpolationFilters: SVGColorInterpolation?

  let stdDeviation: StdDeviation?

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    stdDeviation = StdDeviation(description: attributes["stdDeviation", default: ""])
    input = SVGFilterInput(rawValue: attributes["in", default: ""])

    colorInterpolationFilters = base.style.colorInterpolationFilters
  }

}

extension SVGFeGaussianBlurElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case stdDeviation
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encodeIfPresent(stdDeviation, forKey: .stdDeviation)
  }
}
