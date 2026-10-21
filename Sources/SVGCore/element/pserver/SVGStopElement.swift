import CoreGraphics
import Foundation

enum StopDimension {
  case absolute(Double)
  case percent(Double)

  var value: CGFloat {
    switch self {
    case .absolute(let v):
      return CGFloat(max(v, 0))
    case .percent(let v):
      return CGFloat(max(v, 0)) / 100.0
    }
  }
}

extension StopDimension: CustomStringConvertible {
  var description: String {
    switch self {
    case .absolute(let v):
      return v.description
    case .percent(let v):
      return "\(v)%"
    }
  }
}

final class SVGStopElement: SVGElement {
  static var type: SVGElementName {
    .stop
  }

  var type: SVGElementName {
    .stop
  }

  let base: SVGBaseElement
  let offset: StopDimension
  let color: SVGColor
  let opacity: Double

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    let attribute = attributes["offset", default: ""].trimmingCharacters(in: .whitespaces)
    if attribute.hasSuffix("%") {
      offset = .percent(Double(String(attribute.dropLast()).trimmingCharacters(in: .whitespaces)) ?? 0)
    } else {
      offset = .absolute(Double(attribute) ?? 0)
    }
    color = base.style.resolved(base.style.stopColor)
    opacity = base.style.stopOpacity
  }
}

extension SVGStopElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case offset
    case color = "stop-color"
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(offset.description, forKey: .offset)
    try container.encode(color, forKey: .color)
  }
}
