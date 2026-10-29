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

  /// The rotation of the character at an index, or `nil` if it isn't rotated.
  func rotation(at index: Int) -> Double? {
    guard let last = rotate.last else { return nil }
    return index < rotate.count ? rotate[index] : last
  }

  /// Whether the character at an index starts a run of its own, because it has a position of its own or is rotated.
  func startsRun(at index: Int) -> Bool {
    index < x.count || index < y.count || index < dx.count || index < dy.count || !rotate.isEmpty
  }

  /// Whether the character at an index starts a text chunk, because it has an absolute position.
  func startsChunk(at index: Int) -> Bool {
    index < x.count || index < y.count
  }
}

/// A run of the characters of text, laid out on one line, and where its glyphs are drawn.
struct PlacedTextRun {
  let line: CTLine
  /// The transform from the coordinates of the line, which the font is scaled in and whose y-axis points up, to the
  /// user space.
  let transform: CGAffineTransform
  /// The rotation of each glyph about its origin, in degrees, or `nil` if the glyphs aren't rotated.
  let rotation: Double?
}

/// Text laid out in runs of characters, with the positions that its element gives them.
///
/// The characters are split into runs where they have positions of their own, and each run is a line of its own. A
/// text chunk starts at each character with an absolute position, and is anchored by `text-anchor` with its width.
/// Text without positions of its characters is one run, as one line.
struct TextLayout {
  let runs: [PlacedTextRun]

  /// - Parameters:
  ///   - text: The characters, with their white space processed.
  ///   - line: Makes the line of a run of characters, or returns `nil` if the text isn't drawn.
  init?(
    text: String, positions: CharacterPositions, anchor: TextAnchor, context: any GeometryContext,
    line: (String) -> CTLine?
  ) {
    let characters = Array(text)
    let textScale = context.textScale
    // The runs, with the index of their first character.
    var starts = [0]
    for index in characters.indices.dropFirst() where positions.startsRun(at: index) {
      starts.append(index)
    }
    struct Run {
      let line: CTLine
      /// The width of the line in the coordinates of the line.
      let width: CGFloat
      let y: CGFloat
      /// The distance from the start of the chunk, in the coordinates of the line.
      let offset: CGFloat
      let rotation: Double?
    }
    struct Chunk {
      let x: CGFloat
      var width: CGFloat = 0
      var runs = [Run]()
    }
    var chunks = [Chunk]()
    var y: CGFloat = 0
    var x: CGFloat = 0
    for (number, start) in starts.enumerated() {
      let end = number + 1 < starts.count ? starts[number + 1] : characters.count
      guard let runLine = line(String(characters[start..<end])) else { return nil }
      if start < positions.x.count {
        x = positions.x[start].value(context: context, mode: .width)
      }
      if start < positions.y.count {
        y = positions.y[start].value(context: context, mode: .height)
      }
      if start < positions.dx.count {
        x += positions.dx[start].value(context: context, mode: .width)
      }
      if start < positions.dy.count {
        y += positions.dy[start].value(context: context, mode: .height)
      }
      if chunks.isEmpty || positions.startsChunk(at: start) {
        chunks.append(Chunk(x: x))
      }
      let width = CTLineGetBoundsWithOptions(runLine, CTLineBoundsOptions()).width
      let chunk = chunks.count - 1
      // The offset of the first run of a chunk is 0, so that text without positions is laid out as one line.
      let offset = chunks[chunk].runs.isEmpty ? 0 : (x - chunks[chunk].x) * textScale
      chunks[chunk].runs.append(
        Run(line: runLine, width: width, y: y, offset: offset, rotation: positions.rotation(at: start)))
      chunks[chunk].width = offset + width
      x += width / textScale
    }
    runs = chunks.flatMap { chunk in
      let anchorOffset: CGFloat =
        switch anchor {
        case .start: 0
        case .middle: -chunk.width / 2
        case .end: -chunk.width
        }
      return chunk.runs.map { run in
        PlacedTextRun(
          line: run.line,
          transform: CGAffineTransform(translationX: chunk.x, y: run.y)
            .scaledBy(x: 1.0 / textScale, y: -1.0 / textScale)
            .translatedBy(x: anchorOffset + run.offset, y: 0),
          rotation: run.rotation)
      }
    }
  }

  /// The bounds of the lines of the runs, which are larger than the bounds of their glyphs.
  var frame: CGRect {
    runs.map { CTLineGetBoundsWithOptions($0.line, CTLineBoundsOptions()).applying($0.transform) }
      .reduce(CGRect.null) { $0.union($1) }
  }

  /// The outlines of the glyphs.
  var path: CGPath {
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
    // The y-axis of the line points up, so a clockwise rotation in the user space is counterclockwise here.
    let rotation = run.rotation.map { CGAffineTransform(rotationAngle: -$0 * .pi / 180) } ?? .identity
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
