import CoreGraphics
import Foundation

final class SVGUseElement: SVGDrawableElement {
  static var type: SVGElementName {
    .use
  }

  var type: SVGElementName {
    .use
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let parentId: String?
  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    // `x` and `y` are geometry properties, which style sheets set, and whose presentation attributes are read as CSS.
    // `width` and `height` are attributes, which take math functions as the lengths of SVG 2 do.
    x = base.style.x
    y = base.style.y
    width = attributes["width"].flatMap { SVGLength(property: $0, isNonNegative: true) }
    height = attributes["height"].flatMap { SVGLength(property: $0, isNonNegative: true) }
    parentId = fragmentID(of: attributes["href"])
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  func contains(index: ObjectIdentifier) -> Bool {
    self.index == index || children.contains(where: { $0.index == index })
  }
}
