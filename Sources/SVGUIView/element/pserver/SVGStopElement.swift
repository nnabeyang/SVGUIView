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

struct SVGStopElement: SVGElement {
  var type: SVGElementName {
    .stop
  }

  func style(with _: CSSStyle, at _: Int) -> any SVGElement {
    self
  }

  let offset: StopDimension
  let color: SVGFill?
  let opacity: Double
  init(attributes: [String: String]) {
    let attribute = attributes["offset", default: ""].trimmingCharacters(in: .whitespaces)
    if attribute.hasSuffix("%") {
      offset = .percent(Double(String(attribute.dropLast()).trimmingCharacters(in: .whitespaces)) ?? 0)
    } else {
      offset = .absolute(Double(attribute) ?? 0)
    }
    color = SVGFill(description: attributes["stop-color", default: "black"])
    opacity = Double(attributes["stop-opacity", default: ""].trimmingCharacters(in: .whitespaces)) ?? 1.0
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
