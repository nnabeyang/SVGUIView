import CoreGraphics
import CoreText
import Foundation

enum TextAnchor: String, CaseIterable {
  case start
  case middle
  case end
}

final class SVGTextElement: ShapeGeometry {
  static var type: SVGElementName {
    .text
  }

  var type: SVGElementName {
    .text
  }

  let base: SVGBaseElement
  /// The `<tspan>` children.
  let children: [any SVGElement]
  /// The characters of the text and its `<tspan>` descendants, with their white space processed.
  let characters: [TextCharacter]
  /// The `<tspan>` descendants that aren't `display: none`, in document order, after `nil` for the text itself,
  /// which the characters belong to.
  private let spans: [SVGTSpanElement?]
  /// The characters of each owner and its descendants.
  private let ownerRanges: [Range<Int>]

  /// The characters of the text, with their white space processed.
  var text: String { String(characters.map(\.character)) }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    var collector = TextCollector()
    collector.collect(base: base, children: children, owner: nil)
    characters = collector.finished()
    spans = collector.owners
    ownerRanges = collector.ranges
  }

  convenience init(base: SVGBaseElement, text _: String, attributes _: [String: String]) {
    self.init(base: base, contents: [])
  }

  /// The elements that the characters belong to: the text itself and its `<tspan>` descendants that aren't
  /// `display: none`, in document order.
  var owners: [any SVGDrawableElement] {
    spans.map { span -> any SVGDrawableElement in
      if let span { span } else { self }
    }
  }

  /// The positions that the text gives its characters.
  var positions: CharacterPositions { CharacterPositions(attributes: base.attributes) }

  /// The text laid out with the positions of its characters, or `nil` if it isn't drawn.
  private func layout(context: any GeometryContext) -> TextLayout? {
    var characters = characters
    // The closest element of a character gives it its position, and the descendants come after their ancestors.
    for (span, range) in zip(spans, ownerRanges).reversed() {
      (span?.positions ?? positions).apply(to: &characters[range], context: context)
    }
    let owners = owners
    return TextLayout(
      characters: characters, anchors: owners.map(\.style.textAnchor), textScale: context.textScale
    ) { text, owner in
      Self.line(of: text, style: owners[owner].style, context: context)
    }
  }

  /// The glyphs of each element of the text that has some, which a span of its own draws with the styles of its
  /// element, or `nil` if the text isn't drawn.
  func spans(in context: any GeometryContext) -> [TextSpan]? {
    guard let layout = layout(context: context) else { return nil }
    let drawn = Set(layout.runs.map(\.owner))
    let owners = owners
    return owners.indices.filter(drawn.contains).map { owner in
      TextSpan(element: owners[owner], path: layout.path(of: [owner]), frame: layout.frame(of: [owner]))
    }
  }

  /// The line of a run of characters in the font of a style, or `nil` if it isn't drawn.
  private static func line(of text: String, style: ComputedStyle, context: any SVGLengthContext) -> CTLine? {
    var attributes: [CFString: Any] = [:]
    let font = style.font
    let modifiedFont: SVGUIFont? = {
      switch font.size {
      case .length(.number(let value)), .length(.pixel(let value)):
        if value == 0 {
          return nil
        }
        if value < 0 {
          return SVGUIFont(name: style.fontFamily, size: .medium, weight: style.fontWeight)
        }
      default:
        break
      }
      return font
    }()
    guard let modifiedFont = modifiedFont else { return nil }
    attributes[kCTFontAttributeName] = modifiedFont.ctFont(context: context, textScale: context.textScale)

    guard
      let attributedText = CFAttributedStringCreate(
        kCFAllocatorDefault,
        text as NSString,
        attributes as CFDictionary)
    else { return nil }
    return CTLineCreateWithAttributedString(attributedText)
  }

  /// The bounds of the lines of text, which are larger than the bounds of its glyphs.
  func frame(in context: any GeometryContext, path _: CGPath?) -> CGRect {
    layout(context: context)?.frame() ?? .zero
  }

  /// The outlines of the glyphs of the text and its `<tspan>` descendants.
  func path(in context: any GeometryContext) -> CGPath? {
    layout(context: context)?.path()
  }

  static func withUnsafeMutablePointer<T>(array: inout [T], from: Int) -> UnsafeMutablePointer<T> {
    let baseAddress = array.withUnsafeMutableBufferPointer { $0.baseAddress! }
    return baseAddress.advanced(by: from)
  }
}

/// The glyphs of an element of text, which are drawn with its styles.
struct TextSpan {
  let element: any SVGDrawableElement
  let path: CGPath
  /// The bounds of the lines of the glyphs.
  let frame: CGRect
}

/// Collects the characters of text and its `<tspan>` descendants in document order, processing their white space
/// across the elements.
private struct TextCollector {
  var characters = [TextCharacter]()
  /// The `<tspan>` elements that the characters belong to, or `nil` for the text itself.
  var owners = [SVGTSpanElement?]()
  var ranges = [Range<Int>]()
  /// Whether the spaces of each owner collapse.
  private var collapses = [Bool]()
  /// Whether the last character kept is a space, which a collapsible space after it collapses into. The start of
  /// the text collapses the spaces at its start.
  private var afterSpace = true

  mutating func collect(base: SVGBaseElement, children: [any SVGElement], owner element: SVGTSpanElement?) {
    let owner = owners.count
    owners.append(element)
    let collapses = base.style.whiteSpace.collapsesSpaces
    self.collapses.append(collapses)
    ranges.append(characters.count..<characters.count)
    let start = characters.count
    for (index, text) in base.texts.enumerated() {
      for character in CSSWhiteSpace.spaced(text) {
        if collapses, character == " ", afterSpace { continue }
        characters.append(TextCharacter(character: character, owner: owner))
        afterSpace = character == " "
      }
      if index < children.count, let tspan = children[index] as? SVGTSpanElement, tspan.display != CSSDisplay.none {
        collect(base: tspan.base, children: tspan.children, owner: tspan)
      }
    }
    ranges[owner] = start..<characters.count
  }

  /// The characters, without the collapsible spaces at the end of the text.
  mutating func finished() -> [TextCharacter] {
    while let last = characters.last, last.character == " ", collapses[last.owner] {
      characters.removeLast()
    }
    for index in ranges.indices {
      ranges[index] = ranges[index].clamped(to: 0..<characters.count)
    }
    return characters
  }
}

extension SVGTextElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case text
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(text, forKey: .text)
  }
}
