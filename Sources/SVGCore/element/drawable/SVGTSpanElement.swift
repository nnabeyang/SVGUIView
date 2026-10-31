import CoreGraphics
import Foundation

/// A `<tspan>`: a span of the text of a `<text>` with styles and positions of its own, which `SVGTextElement` lays
/// out. It's rendered only in text. An `<a>` in text is a span too.
final class SVGTSpanElement: SVGDrawableElement {
  static var type: SVGElementName {
    .tspan
  }

  /// `tspan`, or `a` for an `<a>` in text.
  var type: SVGElementName {
    base.name
  }

  let base: SVGBaseElement
  /// The `<tspan>` and `<a>` children.
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
