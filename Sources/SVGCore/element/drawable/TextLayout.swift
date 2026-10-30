import CoreGraphics
import CoreText
import Foundation

/// The positions that an element gives the characters of its text: the `x`, `y`, `dx`, `dy` and `rotate` attributes,
/// whose i-th values apply to the i-th character.
struct CharacterPositions {
  let x: [SVGLength]
  let y: [SVGLength]
  let dx: [SVGLength]
  let dy: [SVGLength]
  /// The rotations in degrees. The last one also applies to the characters after the list.
  let rotate: [Double]

  init(attributes: [String: String]) {
    x = Self.lengths(attributes["x"])
    y = Self.lengths(attributes["y"])
    dx = Self.lengths(attributes["dx"])
    dy = Self.lengths(attributes["dy"])
    rotate = Self.numbers(attributes["rotate"])
  }

  /// The items of a list separated by white space or commas.
  private static func items(_ text: String?) -> [Substring] {
    text?.split { $0 == "," || $0.isWhitespace } ?? []
  }

  /// A list of lengths, which is empty if one of them isn't valid.
  private static func lengths(_ text: String?) -> [SVGLength] {
    let lengths = items(text).map { SVGLength(String($0)) }
    return lengths.contains(nil) ? [] : lengths.compactMap(\.self)
  }

  /// A list of numbers, which is empty if one of them isn't valid.
  private static func numbers(_ text: String?) -> [Double] {
    let numbers = items(text).map { Double($0) }
    return numbers.contains(nil) ? [] : numbers.compactMap(\.self)
  }

  /// Gives the characters of an element, in order, the positions that they don't have yet.
  ///
  /// The characters of the descendants of the element are given their positions first, so that the positions of
  /// the closest element win.
  func apply(to characters: inout ArraySlice<TextCharacter>, context: any GeometryContext) {
    for (number, index) in characters.indices.enumerated() {
      if characters[index].x == nil, number < x.count {
        characters[index].x = x[number].value(context: context, mode: .width)
      }
      if characters[index].y == nil, number < y.count {
        characters[index].y = y[number].value(context: context, mode: .height)
      }
      if characters[index].dx == nil, number < dx.count {
        characters[index].dx = dx[number].value(context: context, mode: .width)
      }
      if characters[index].dy == nil, number < dy.count {
        characters[index].dy = dy[number].value(context: context, mode: .height)
      }
      if characters[index].rotate == nil, let last = rotate.last {
        characters[index].rotate = number < rotate.count ? rotate[number] : last
      }
    }
  }
}

/// A character of text, the element that it belongs to, and the position that the elements give it.
struct TextCharacter {
  let character: Character
  /// The element that the character belongs to, as an index into the elements of the text.
  let owner: Int
  var x: CGFloat?
  var y: CGFloat?
  var dx: CGFloat?
  var dy: CGFloat?
  /// The rotation in degrees.
  var rotate: Double?

  /// Whether the character starts a run of its own, because it has a position of its own or is rotated.
  var startsRun: Bool { x != nil || y != nil || dx != nil || dy != nil || rotate != nil }

  /// Whether the character starts a text chunk, because it has an absolute position.
  var startsChunk: Bool { x != nil || y != nil }
}

/// A run of the characters of text, laid out on one line, and where its glyphs are drawn.
struct PlacedTextRun {
  let line: CTLine
  /// The element of the characters, as an index into the elements of the text.
  let owner: Int
  /// The width of the line, in the coordinates of the line.
  let width: CGFloat
  /// The transform from the coordinates of the line, which the font is scaled in and whose y-axis points up, to the
  /// user space.
  let transform: CGAffineTransform
  /// The rotation of each glyph about its origin, in degrees, or `nil` if the glyphs aren't rotated.
  let rotation: Double?
}

/// Text laid out in runs of characters, with the positions that its elements give them.
///
/// The characters are split into runs where they have positions of their own or belong to another element, and each
/// run is a line of its own. A text chunk starts at each character with an absolute position, and is anchored by the
/// `text-anchor` of the element of its first character with its width. Text of one element without positions of its
/// characters is one run, as one line.
struct TextLayout {
  let runs: [PlacedTextRun]

  /// - Parameters:
  ///   - characters: The characters, with their white space processed.
  ///   - anchors: The `text-anchor` of each element of the text.
  ///   - baselineOffsets: How far down the glyphs of each element of the text are drawn from the current text
  ///     position, in the user space, for its baselines and its `baseline-shift`.
  ///   - line: Makes the line of a run of characters of an element, with the space after its last character, or
  ///     returns `nil` if they aren't drawn. The space after the last character of a chunk doesn't count in its
  ///     width, which it's anchored with.
  init?(
    characters: [TextCharacter], anchors: [TextAnchor], baselineOffsets: [CGFloat], textScale: CGFloat,
    line: (String, Int) -> (line: CTLine, trailingSpace: CGFloat)?
  ) {
    // The runs, with the index of their first character.
    var starts = [0]
    for index in characters.indices.dropFirst()
    where characters[index].startsRun || characters[index].owner != characters[index - 1].owner {
      starts.append(index)
    }
    struct Run {
      let line: CTLine
      let owner: Int
      /// The width of the line in the coordinates of the line.
      let width: CGFloat
      let y: CGFloat
      /// The distance from the start of the chunk, in the coordinates of the line.
      let offset: CGFloat
      let rotation: Double?
    }
    struct Chunk {
      let x: CGFloat
      let anchor: TextAnchor
      var width: CGFloat = 0
      var runs = [Run]()
    }
    var chunks = [Chunk]()
    var y: CGFloat = 0
    var x: CGFloat = 0
    for (number, start) in starts.enumerated() {
      let end = number + 1 < starts.count ? starts[number + 1] : characters.count
      // Text without characters is one empty run of the text itself.
      let first = start < characters.count ? characters[start] : TextCharacter(character: " ", owner: 0)
      x = first.x ?? x
      y = first.y ?? y
      x += first.dx ?? 0
      y += first.dy ?? 0
      if chunks.isEmpty || first.startsChunk {
        chunks.append(Chunk(x: x, anchor: anchors[first.owner]))
      }
      guard let (runLine, trailingSpace) = line(String(characters[start..<end].map(\.character)), first.owner)
      else { continue }
      let width = CTLineGetBoundsWithOptions(runLine, CTLineBoundsOptions()).width
      let chunk = chunks.count - 1
      // The offset of the first run of a chunk is 0, so that text without positions is laid out as one line.
      let offset = chunks[chunk].runs.isEmpty ? 0 : (x - chunks[chunk].x) * textScale
      chunks[chunk].runs.append(
        Run(
          line: runLine, owner: first.owner, width: width, y: y + baselineOffsets[first.owner], offset: offset,
          rotation: first.rotate))
      chunks[chunk].width = offset + width - trailingSpace
      x += width / textScale
    }
    runs = chunks.flatMap { chunk in
      let anchorOffset: CGFloat =
        switch chunk.anchor {
        case .start: 0
        case .middle: -chunk.width / 2
        case .end: -chunk.width
        }
      return chunk.runs.map { run in
        PlacedTextRun(
          line: run.line, owner: run.owner, width: run.width,
          transform: CGAffineTransform(translationX: chunk.x, y: run.y)
            .scaledBy(x: 1.0 / textScale, y: -1.0 / textScale)
            .translatedBy(x: anchorOffset + run.offset, y: 0),
          rotation: run.rotation)
      }
    }
    if runs.isEmpty { return nil }
  }

  /// The bounds of the lines of the runs of the elements, which are larger than the bounds of their glyphs.
  func frame(of owners: Set<Int>? = nil) -> CGRect {
    runs.filter { owners?.contains($0.owner) ?? true }
      .map { CTLineGetBoundsWithOptions($0.line, CTLineBoundsOptions()).applying($0.transform) }
      .reduce(CGRect.null) { $0.union($1) }
  }

  /// The rotation of the glyphs of a run about their origins, in the coordinates of its line.
  static func rotation(of run: PlacedTextRun) -> CGAffineTransform {
    // The y-axis of the line points up, so a clockwise rotation in the user space is counterclockwise here.
    run.rotation.map { CGAffineTransform(rotationAngle: -$0 * .pi / 180) } ?? .identity
  }

  /// The outlines of the glyphs of the elements.
  func path(of owners: Set<Int>? = nil) -> CGPath {
    let runs = runs.filter { owners?.contains($0.owner) ?? true }
    if runs.count == 1 {
      return Self.glyphs(of: runs[0]).applying(runs[0].transform)
    }
    let path = CGMutablePath()
    for run in runs {
      path.addPath(Self.glyphs(of: run), transform: run.transform)
    }
    return path
  }

  /// The outlines of the glyphs of a run, in the coordinates of its line.
  private static func glyphs(of run: PlacedTextRun) -> CGMutablePath {
    let letters = CGMutablePath()
    let rotation = rotation(of: run)
    let glyphRuns = CTLineGetGlyphRuns(run.line)
    for i in 0..<CFArrayGetCount(glyphRuns) {
      let glyphRun = unsafeBitCast(CFArrayGetValueAtIndex(glyphRuns, i), to: CTRun.self)
      let fontPointer = CFDictionaryGetValue(
        CTRunGetAttributes(glyphRun), Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
      let runFont = unsafeBitCast(fontPointer, to: CTFont.self)
      let length = CTRunGetGlyphCount(glyphRun) as Int
      var glyphs = [CGGlyph](repeating: .init(), count: length)
      var positions = [CGPoint](repeating: CGPoint(), count: length)
      let range = CFRange(location: 0, length: length)
      CTRunGetGlyphs(glyphRun, range, &glyphs)
      CTRunGetPositions(glyphRun, range, &positions)
      for index in 0..<glyphs.count {
        let position = positions[index]
        guard let letter = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
        letters.addPath(
          letter, transform: rotation.concatenating(CGAffineTransform(translationX: position.x, y: position.y)))
      }
    }
    return letters
  }
}
