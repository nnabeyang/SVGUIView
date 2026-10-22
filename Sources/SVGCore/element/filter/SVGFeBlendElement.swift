import CoreGraphics
import Foundation

enum SVGBlendMode: String {
  case normal
  case multiply
  case screen
  case overlay
  case darken
  case lighten
  case colorDodge = "color-dodge"
  case colorBurn = "color-burn"
  case hardLight = "hard-light"
  case softLight = "soft-light"
  case difference
  case exclusion
  case saturation
  case color
  case luminosity
  case hue

  var toCgBlendMode: CGBlendMode {
    switch self {
    case .normal:
      return .normal
    case .multiply:
      return .multiply
    case .screen:
      return .screen
    case .overlay:
      return .overlay
    case .darken:
      return .darken
    case .lighten:
      return .lighten
    case .colorDodge:
      return .colorDodge
    case .colorBurn:
      return .colorBurn
    case .hardLight:
      return .hardLight
    case .softLight:
      return .softLight
    case .difference:
      return .difference
    case .exclusion:
      return .exclusion
    case .saturation:
      return .saturation
    case .color:
      return .color
    case .luminosity:
      return .luminosity
    case .hue:
      return .hue
    }
  }
}

final class SVGFeBlendElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feBlend
  }

  var type: SVGElementName {
    .feBlend
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let mode: SVGBlendMode?
  let input: SVGFilterInput?
  let input2: SVGFilterInput?

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    mode = SVGBlendMode(rawValue: attributes["mode", default: ""])
    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    input2 = SVGFilterInput(rawValue: attributes["in2", default: ""])
  }

}

extension SVGFeBlendElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
