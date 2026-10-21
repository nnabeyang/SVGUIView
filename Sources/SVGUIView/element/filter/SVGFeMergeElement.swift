import CoreGraphics
import Foundation

final class SVGFeMergeElement: SVGElement, SVGFilterPrimitiveElement {
  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?
  let colorInterpolationFilters: SVGColorInterpolation?

  static var type: SVGElementName {
    .feMergeNode
  }

  var type: SVGElementName {
    .feMergeNode
  }

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
    colorInterpolationFilters = base.style.colorInterpolationFilters
  }

}

extension SVGFeMergeElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
