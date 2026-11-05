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
  /// The `<tspan>` and `<textPath>` children.
  let children: [any SVGElement]
  /// The characters of the text and its spans, with every `<textPath>` in it.
  private let content: TextContent

  /// The characters of the text and its `<tspan>` and `<textPath>` descendants, with their white space processed.
  var characters: [TextCharacter] { content.characters }

  /// The characters of the text, with their white space processed.
  var text: String { String(characters.map(\.character)) }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    content = TextContent(base: base, children: children) { _ in true }
  }

  convenience init(base: SVGBaseElement, text _: String, attributes _: [String: String]) {
    self.init(base: base, contents: [])
  }

  /// The elements that the characters belong to: the text itself and its `<tspan>` and `<textPath>` descendants
  /// that aren't `display: none`, in document order.
  private func owners(of content: TextContent) -> [any SVGDrawableElement] {
    content.owners.map { span -> any SVGDrawableElement in
      if let span { span } else { self }
    }
  }

  /// The positions that the text gives its characters.
  var positions: CharacterPositions { CharacterPositions(attributes: base.attributes) }

  /// The characters of the text and its spans, and the paths of its `<textPath>` elements. A `<textPath>` without a
  /// path isn't rendered, with its characters.
  private func renderedContent(in context: any GeometryContext) -> (content: TextContent, paths: [PathMeasure]) {
    let paths = content.textPaths.map { context.path(of: $0) }
    if !paths.contains(where: { $0 == nil }) { return (content, paths.compactMap(\.self)) }
    let rendered = Set(zip(content.textPaths, paths).compactMap { $1 == nil ? nil : ObjectIdentifier($0) })
    let content = TextContent(base: base, children: children) { rendered.contains(ObjectIdentifier($0)) }
    return (content, content.textPaths.compactMap { context.path(of: $0) })
  }

  /// The text laid out with the positions of its characters, or `nil` if it isn't drawn.
  private func layout(of content: TextContent, paths: [PathMeasure], context: any GeometryContext) -> TextLayout? {
    var characters = content.characters
    // The closest element of a character gives it its position, and the descendants come after their ancestors.
    for (span, range) in zip(content.owners, content.ranges).reversed() {
      (span?.positions ?? positions).apply(to: &characters[range], context: context)
    }
    let owners = owners(of: content)
    let pathLayouts = zip(content.textPaths, paths).map { textPath, measure in
      let offset: CGFloat =
        if case .percent(let percent) = textPath.startOffset {
          percent / 100 * measure.length
        } else {
          textPath.startOffset.value(context: context, mode: .other)
        }
      return TextPathLayout(
        measure: measure, startOffset: offset.isFinite ? offset : 0, stretches: textPath.stretchesGlyphs)
    }
    return TextLayout(
      characters: characters, anchors: owners.map(\.style.textAnchor),
      baselineOffsets: baselineOffsets(of: content, context: context), textScale: context.textScale,
      paths: pathLayouts
    ) { text, owner in
      Self.line(of: text, style: owners[owner].style, context: context)
    }
  }

  /// The text laid out, with the characters that it's laid out from, or `nil` if it isn't drawn.
  private func layout(context: any GeometryContext) -> (layout: TextLayout, content: TextContent)? {
    let (content, paths) = renderedContent(in: context)
    return layout(of: content, paths: paths, context: context).map { ($0, content) }
  }

  /// The shapes that the elements of the text draw with their styles, in the order that they're drawn, or `nil` if
  /// the text isn't drawn.
  ///
  /// Each element that has glyphs or draws lines of `text-decoration` has a shape of its glyphs, and its underlines
  /// and overlines, which are drawn under the glyphs of the elements after it. Its lines through the text come after
  /// all the glyphs.
  func spans(in context: any GeometryContext) -> [TextSpan]? {
    guard let (layout, content) = layout(context: context) else { return nil }
    let owners = owners(of: content)
    let glyphs = Set(layout.runs.map(\.owner))
    let lines = decorationLines(of: layout, content: content, context: context)
    var spans = [TextSpan]()
    for owner in owners.indices where glyphs.contains(owner) || lines.under[owner] != nil {
      let path = CGMutablePath()
      if glyphs.contains(owner) {
        path.addPath(layout.path(of: [owner]))
      }
      if let under = lines.under[owner] {
        path.addPath(under)
      }
      spans.append(TextSpan(element: owners[owner], path: path, frame: layout.frame(of: [owner])))
    }
    for owner in owners.indices {
      if let through = lines.through[owner] {
        spans.append(TextSpan(element: owners[owner], path: through, frame: .null))
      }
    }
    return spans
  }

  /// The lines of `text-decoration` that each element draws: its underlines and overlines, and its lines through the
  /// text, in the user space.
  ///
  /// A line decorates the characters of the element that declares it and of its descendants, and it's drawn with
  /// the styles and the font of that element, or of the text if an element around the text declares it.
  ///
  /// A run on a path has a piece of each line under each of its glyphs.
  private func decorationLines(
    of layout: TextLayout, content: TextContent, context: any GeometryContext
  ) -> (under: [Int: CGMutablePath], through: [Int: CGMutablePath]) {
    var under = [Int: CGMutablePath]()
    var through = [Int: CGMutablePath]()
    let owners = owners(of: content)
    for run in layout.runs {
      for line in [TextDecorationLines.underline, .overline, .lineThrough]
      where owners[run.owner].style.textDecoration.contains(line) {
        let decorator = decorator(of: line, for: run.owner, content: content)
        guard let font = Self.font(of: owners[decorator].style, context: context) else { continue }
        var thickness = CTFontGetUnderlineThickness(font)
        let center: CGFloat
        switch line {
        case .underline:
          center = CTFontGetUnderlinePosition(font)
        case .overline:
          center = CTFontGetAscent(font)
        default:
          let strikeout = Self.strikeout(of: font)
          center = strikeout?.position ?? CTFontGetXHeight(font) / 2
          thickness = strikeout?.thickness ?? thickness
        }
        let paths = line == .lineThrough ? through : under
        let path = paths[decorator] ?? CGMutablePath()
        if let glyphs = run.glyphs {
          for glyph in glyphs.compactMap(\.self) {
            let rect = CGRect(x: 0, y: center - thickness / 2, width: glyph.advance, height: thickness)
            glyph.add(rect, to: path)
          }
        } else {
          let rect = CGRect(x: 0, y: center - thickness / 2, width: run.width, height: thickness)
          path.addRect(rect, transform: TextLayout.rotation(of: run).concatenating(run.transform))
        }
        if line == .lineThrough {
          through[decorator] = path
        } else {
          under[decorator] = path
        }
      }
    }
    return (under, through)
  }

  /// The position of the line through text above the baseline, and its thickness, from the OS/2 table of a font,
  /// or `nil` if the font has none. Core Text gives the underline of a font, but not this line.
  private static func strikeout(of font: CTFont) -> (position: CGFloat, thickness: CGFloat)? {
    // yStrikeoutPosition and yStrikeoutSize.
    guard let position = os2Value(of: font, at: 28), let thickness = os2Value(of: font, at: 26) else { return nil }
    return (position, thickness)
  }

  /// A value of the OS/2 table of a font, an `FWORD` at a byte offset, in the coordinates of the font, or `nil` if
  /// the font has no such table.
  private static func os2Value(of font: CTFont, at offset: Int) -> CGFloat? {
    guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?, table.count >= offset + 2
    else { return nil }
    let start = table.startIndex + offset
    let value = Int16(bitPattern: UInt16(table[start]) << 8 | UInt16(table[start + 1]))
    return CGFloat(value) * CTFontGetSize(font) / CGFloat(CTFontGetUnitsPerEm(font))
  }

  /// How far down the glyphs of each owner are drawn from the current text position, in the user space: the
  /// position of the baseline that it aligns by, minus the sum of the `baseline-shift` of the tspans from the text
  /// to the owner.
  private func baselineOffsets(of content: TextContent, context: any GeometryContext) -> [CGFloat] {
    let owners = owners(of: content)
    let parents = content.parents
    let textScale = context.textScale
    var shifts = [CGFloat]()
    var offsets = [CGFloat]()
    for owner in owners.indices {
      let style = owners[owner].style
      guard let font = Self.font(of: style, context: context) else {
        shifts.append(parents[owner].map { shifts[$0] } ?? 0)
        offsets.append(0)
        continue
      }
      // The baseline-shift of a tspan adds to the ones of the tspans that it's in.
      var shift = parents[owner].map { shifts[$0] } ?? 0
      if owner != 0 {
        switch style.baselineShift {
        case .baseline:
          break
        case .sub:
          // Half of the height of the font, as browsers do. The subscript offset of the font is much smaller.
          shift -= (CTFontGetAscent(font) + CTFontGetDescent(font)) / 2 / textScale
        case .super:
          shift += (CTFontGetAscent(font) + CTFontGetDescent(font)) / 2 / textScale
        case .length(.percent(let percent)):
          shift += percent / 100 * CTFontGetSize(font) / textScale
        case .length(let length):
          shift += length.value(context: context, mode: .other)
        }
      }
      shifts.append(shift)
      let baseline = style.alignmentBaseline.baseline ?? style.dominantBaseline.baseline
      offsets.append(Self.position(of: baseline, in: font) / textScale - shift)
    }
    return offsets
  }

  /// The position of a baseline above the alphabetic baseline, in the coordinates of a font.
  ///
  /// Core Text gives the ascent, the descent and the x-height, and the other baselines are placed from them as
  /// browsers do: the hanging baseline at 0.8 of the ascent, and the mathematical baseline at half of it.
  private static func position(of baseline: TextBaseline, in font: CTFont) -> CGFloat {
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    return switch baseline {
    case .alphabetic: 0
    case .ideographic, .textAfterEdge: -descent
    case .textBeforeEdge: ascent
    case .hanging: ascent * 0.8
    case .mathematical: ascent / 2
    case .central: (ascent - descent) / 2
    case .middle: CTFontGetXHeight(font) / 2
    }
  }

  /// The element that draws a line of `text-decoration` on the characters of an element: the closest element of
  /// the text, from the element to the text, that declares the line, or the text itself.
  private func decorator(of line: TextDecorationLines, for owner: Int, content: TextContent) -> Int {
    var element: Int? = owner
    let owners = owners(of: content)
    while let current = element {
      if owners[current].base.cascaded.declared(TextDecorationProperty.self)?.contains(line) == true {
        return current
      }
      element = content.parents[current]
    }
    return 0
  }

  /// The line of a run of characters in the font of a style, spaced by its `letter-spacing` and `word-spacing`, and
  /// the space after its last character, or `nil` if it isn't drawn.
  private static func line(
    of text: String, style: ComputedStyle, context: any SVGLengthContext
  ) -> (line: CTLine, trailingSpace: CGFloat)? {
    guard let font = font(of: style, context: context),
      let attributedText = CFAttributedStringCreate(
        kCFAllocatorDefault, text as NSString, [kCTFontAttributeName: font] as CFDictionary)
    else { return nil }
    // The line is in the font, which is scaled by the text scale. A percentage is of the size of the font.
    func spacing(_ length: SVGLength) -> CGFloat {
      let value: CGFloat =
        if case .percent(let percent) = length {
          percent / 100 * CTFontGetSize(font)
        } else {
          length.value(context: context, mode: .other) * context.textScale
        }
      return value.isFinite ? value : 0
    }
    let letter = spacing(style.letterSpacing)
    let word = spacing(style.wordSpacing)
    // A kern of 0 turns the kerning of the font off, so text without spacings has no kern.
    guard letter != 0 || word != 0,
      let spaced = CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0, attributedText)
    else { return (CTLineCreateWithAttributedString(attributedText), 0) }
    var offset = 0
    var kern: CGFloat = 0
    for character in text {
      let length = character.utf16.count
      // word-spacing applies to the spaces that separate words.
      kern = letter + (character == " " || character == "\u{A0}" ? word : 0)
      if kern != 0 {
        CFAttributedStringSetAttribute(
          spaced, CFRange(location: offset, length: length), kCTKernAttributeName, kern as CFNumber)
      }
      offset += length
    }
    return (CTLineCreateWithAttributedString(spaced), kern)
  }

  /// The font of a style, scaled by the text scale, or `nil` if its text isn't drawn.
  private static func font(of style: ComputedStyle, context: any SVGLengthContext) -> CTFont? {
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
    return modifiedFont.ctFont(context: context, textScale: context.textScale)
  }

  /// The bounds of the lines of text, which are larger than the bounds of its glyphs.
  func frame(in context: any GeometryContext, path _: CGPath?) -> CGRect {
    layout(context: context)?.layout.frame() ?? .zero
  }

  /// The outlines of the glyphs of the text and its `<tspan>` descendants, and the lines of their `text-decoration`.
  func path(in context: any GeometryContext) -> CGPath? {
    guard let (layout, content) = layout(context: context) else { return nil }
    let owners = owners(of: content)
    guard content.characters.contains(where: { !owners[$0.owner].style.textDecoration.isEmpty }) else {
      return layout.path()
    }
    let path = CGMutablePath()
    path.addPath(layout.path())
    let lines = decorationLines(of: layout, content: content, context: context)
    for line in Array(lines.under.values) + Array(lines.through.values) {
      path.addPath(line)
    }
    return path
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

/// The characters of text and its spans, and the elements that they belong to.
private struct TextContent {
  /// The characters, with their white space processed.
  let characters: [TextCharacter]
  /// The spans that aren't `display: none`, in document order, after `nil` for the text itself, which the
  /// characters belong to.
  let owners: [SVGTSpanElement?]
  /// The characters of each owner and its descendants.
  let ranges: [Range<Int>]
  /// The owner that each owner is in, or `nil` for the text itself.
  let parents: [Int?]
  /// The `<textPath>` elements whose characters are laid out along their paths, which the paths of the characters
  /// index.
  let textPaths: [SVGTSpanElement]

  /// - Parameter rendersTextPath: Whether a `<textPath>` child of the text is rendered. One that isn't is left out
  ///   with its characters.
  init(base: SVGBaseElement, children: [any SVGElement], rendersTextPath: @escaping (SVGTSpanElement) -> Bool) {
    var collector = TextCollector(rendersTextPath: rendersTextPath)
    collector.collect(base: base, children: children, owner: nil)
    characters = collector.finished()
    owners = collector.owners
    ranges = collector.ranges
    parents = collector.parents
    textPaths = collector.textPaths
  }
}

/// Collects the characters of text and its spans in document order, processing their white space across the
/// elements.
private struct TextCollector {
  let rendersTextPath: (SVGTSpanElement) -> Bool
  var characters = [TextCharacter]()
  /// The spans that the characters belong to, or `nil` for the text itself.
  var owners = [SVGTSpanElement?]()
  var ranges = [Range<Int>]()
  /// The owner that each owner is in, or `nil` for the text itself.
  var parents = [Int?]()
  var textPaths = [SVGTSpanElement]()
  /// The `<textPath>` whose characters are being collected, as an index into the text paths.
  private var path: Int?
  /// The owner whose characters are being collected.
  private var current: Int?
  /// Whether the spaces of each owner collapse.
  private var collapses = [Bool]()
  /// Whether the last character kept is a space, which a collapsible space after it collapses into. The start of
  /// the text collapses the spaces at its start.
  private var afterSpace = true

  init(rendersTextPath: @escaping (SVGTSpanElement) -> Bool) {
    self.rendersTextPath = rendersTextPath
  }

  mutating func collect(base: SVGBaseElement, children: [any SVGElement], owner element: SVGTSpanElement?) {
    let owner = owners.count
    owners.append(element)
    parents.append(current)
    let outer = current
    current = owner
    defer { current = outer }
    let collapses = base.style.whiteSpace.collapsesSpaces
    self.collapses.append(collapses)
    ranges.append(characters.count..<characters.count)
    let start = characters.count
    for (index, text) in base.texts.enumerated() {
      for character in CSSWhiteSpace.spaced(text) {
        if collapses, character == " ", afterSpace { continue }
        characters.append(TextCharacter(character: character, owner: owner, path: path))
        afterSpace = character == " "
      }
      if index < children.count, let tspan = children[index] as? SVGTSpanElement, tspan.base.passesConditions,
        tspan.display != CSSDisplay.none
      {
        if tspan.type == .textPath {
          guard rendersTextPath(tspan) else { continue }
          path = textPaths.count
          textPaths.append(tspan)
          collect(base: tspan.base, children: tspan.children, owner: tspan)
          path = nil
        } else {
          collect(base: tspan.base, children: tspan.children, owner: tspan)
        }
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
