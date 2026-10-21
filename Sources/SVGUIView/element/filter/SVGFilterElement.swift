import CoreGraphics
import Foundation

final class SVGFilterElement: SVGDrawableElement {
  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let filterUnits: SVGUnitType?
  let primitiveUnits: SVGUnitType?

  let colorInterpolation: SVGColorInterpolation?
  let colorInterpolationFilters: SVGColorInterpolation?

  static var type: SVGElementName {
    .filter
  }

  var type: SVGElementName {
    .filter
  }

  var transform: CGAffineTransform {
    .identity
  }

  let children: [any SVGElement]

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    colorInterpolation = base.style.colorInterpolation
    colorInterpolationFilters = base.style.colorInterpolationFilters
    x = .init(attributes["x"])
    y = .init(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    filterUnits = SVGUnitType(rawValue: attributes["filterUnits", default: ""])
    primitiveUnits = SVGUnitType(rawValue: attributes["primitiveUnits", default: ""])
  }

  func toPath(context _: SVGContext) -> CGPath? {
    nil
  }

  func filter(context: inout SVGBaseContext) {
    if let id = id, context.filters[id] == nil {
      context.setFilter(id: id, value: self)
    }
  }
}

extension SVGFilterElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
    case fill
  }

  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
