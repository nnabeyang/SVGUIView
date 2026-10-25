import CoreGraphics
import Foundation

package enum SVGColorInterpolation: String, CaseIterable, Sendable {
  case sRGB
  case linearRGB

  /// The color space that colors are interpolated in.
  package var colorSpace: CGColorSpace {
    switch self {
    case .sRGB:
      CGColorSpace(name: CGColorSpace.sRGB)!
    case .linearRGB:
      CGColorSpace(name: CGColorSpace.linearSRGB)!
    }
  }
}

final class SVGMaskElement: SVGDrawableElement {
  let base: SVGBaseElement
  let colorInterpolation: SVGColorInterpolation?
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  static var type: SVGElementName {
    .mask
  }

  var type: SVGElementName {
    .mask
  }

  let children: [any SVGElement]
  let maskContentUnits: SVGUnitType?

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    colorInterpolation = base.style.colorInterpolation
    x = .init(attributes["x"])
    y = .init(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    maskContentUnits = SVGUnitType(rawValue: attributes["maskContentUnits", default: ""])
  }

  func mask(context: inout SVGBaseContext) {
    if let id = id, context.masks[id] == nil {
      context.setMask(id: id, value: self)
    }
  }
}

extension SVGMaskElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
    case fill
  }

  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
