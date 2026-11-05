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

  /// The ID of the `<path>` or the basic shape that a `<textPath>` lays its characters out along, or `nil` if it
  /// references none.
  var pathID: String? {
    guard let href = base.attributes["href"]?.trimmingCharacters(in: .whitespaces), href.hasPrefix("#") else {
      return nil
    }
    return String(href.dropFirst())
  }

  /// The path data of the `path` attribute of a `<textPath>` up to its first error, which it lays its characters out
  /// along instead of the path that it references if the data has a segment.
  var pathData: PathData? {
    base.attributes["path"].map(PathData.init)
  }

  /// Whether a `<textPath>` places its characters on the right side of its path, which reverses the path.
  var isOnRightSide: Bool {
    base.attributes["side"]?.trimmingCharacters(in: .whitespaces) == "right"
  }

  /// Whether a `<textPath>` bends its glyphs along its path, instead of only placing them on it.
  var stretchesGlyphs: Bool {
    base.attributes["method"]?.trimmingCharacters(in: .whitespaces) == "stretch"
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
