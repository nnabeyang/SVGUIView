import CoreGraphics
import Foundation

/// A `<tspan>`: a span of the text of a `<text>` with styles and positions of its own, which `SVGTextElement` lays
/// out. It's rendered only in text.
final class SVGTSpanElement: SVGDrawableElement {
  static var type: SVGElementName {
    .tspan
  }

  var type: SVGElementName {
    .tspan
  }

  let base: SVGBaseElement
  /// The `<tspan>` children.
  let children: [any SVGElement]
  let positions: CharacterPositions

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    positions = CharacterPositions(attributes: base.attributes)
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }
}

extension SVGTSpanElement {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
