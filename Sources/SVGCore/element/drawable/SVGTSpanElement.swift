import CoreGraphics
import Foundation

/// A `<tspan>`: a span of the text of a `<text>` with styles and positions of its own, which `SVGTextElement` lays
/// out. It's rendered only in text. An `<a>` in text is a span too, and so is a `<textPath>`, whose characters are
/// laid out along a path.
final class SVGTSpanElement: SVGDrawableElement {
  static var type: SVGElementName {
    .tspan
  }

  /// `tspan`, `textPath`, or `a` for an `<a>` in text.
  var type: SVGElementName {
    base.name
  }

  let base: SVGBaseElement
  /// The `<tspan>` and `<a>` children.
  let children: [any SVGElement]
  /// The positions that the span gives its characters. A `<textPath>` gives none.
  let positions: CharacterPositions

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    positions = CharacterPositions(attributes: base.name == .textPath ? [:] : base.attributes)
  }

  /// The ID of the `<path>` that a `<textPath>` lays its characters out along, or `nil` if it references none.
  var pathID: String? {
    guard let href = base.attributes["href"]?.trimmingCharacters(in: .whitespaces), href.hasPrefix("#") else {
      return nil
    }
    return String(href.dropFirst())
  }

  /// How far along its path a `<textPath>` starts its characters, where a percentage is of the length of the path.
  var startOffset: SVGLength {
    SVGLength(base.attributes["startOffset"]) ?? .number(0)
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
