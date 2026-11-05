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
  /// The path that the character is laid out along, as an index into the paths of the text, or `nil` if it isn't in
  /// a `<textPath>`.
  var path: Int?

  init(character: Character, owner: Int, path: Int? = nil) {
    self.character = character
    self.owner = owner
    self.path = path
  }

  /// Whether the character starts a text chunk, because it has an absolute position.
  var startsChunk: Bool { x != nil || y != nil }
}

/// The characters of text shaped as one line, and ordered for bidirectional text, before they're placed.
struct TextLine {
  let line: CTLine
  /// The character of each UTF-16 code unit of the line, as an index into the characters of the text.
  let characters: [Int]
  /// The space that `letter-spacing` and `word-spacing` add after each character of the text, in the coordinates of
  /// the line.
  let spacings: [CGFloat]
}

/// A glyph of text and where it's drawn.
struct PlacedGlyph {
  /// The element of the character of the glyph, as an index into the elements of the text.
  var owner = 0
  var font: CTFont? = nil
  var glyph = CGGlyph()
  /// The transform from the coordinates of the line, with the origin at the origin of the glyph, to the user space.
  let transform: CGAffineTransform
  /// The advance of the glyph, in the coordinates of the line.
  let advance: CGFloat
  /// How the glyph is bent along its path, instead of the transform, or `nil` if it isn't.
  var warp: GlyphWarp? = nil
  /// Whether the glyph is on a line of the text with its baseline horizontal, so that the lines of `text-decoration`
  /// of the glyphs next to it go on as one line.
  var isStraight = false

  /// Adds a path in the coordinates of the line, with the origin at the origin of the glyph, to a path in the user
  /// space.
  func add(_ path: CGPath, to target: CGMutablePath) {
    if let warp {
      target.addPath(warp.bend(path))
    } else {
      target.addPath(path, transform: transform)
    }
  }

  /// Adds a rectangle in the coordinates of the line, with the origin at the origin of the glyph, to a path in the
  /// user space. A glyph that's bent bends the rectangle with it, in pieces along its width.
  func add(_ rect: CGRect, to target: CGMutablePath) {
    guard let warp else {
      target.addRect(rect, transform: transform)
      return
    }
    let pieces = 8
    let xs = (0...pieces).map { rect.minX + rect.width * CGFloat($0) / CGFloat(pieces) }
    let outline = CGMutablePath()
    outline.addLines(between: xs.map { CGPoint(x: $0, y: rect.minY) } + xs.reversed().map { CGPoint(x: $0, y: rect.maxY) })
    outline.closeSubpath()
    target.addPath(warp.bend(outline))
  }
}

/// How a glyph is bent along a path, as `method="stretch"` of a `<textPath>` bends it: each point of its outline,
/// with the control points of its curves, is moved to the point of the path at its distance along the path, and
/// across the path by its distance from the baseline. Beyond the ends of the path, the points go on in the direction
/// of the path at its end.
struct GlyphWarp {
  let measure: PathMeasure
  /// The transform of the outline in the coordinates of the line before it's bent, with the origin at the origin of
  /// the glyph.
  let transform: CGAffineTransform
  /// The distance along the path of the origin of the glyph.
  let start: CGFloat
  /// How far across the path the baseline is.
  let y: CGFloat
  let textScale: CGFloat

  /// A point in the coordinates of the line, with the origin at the origin of the glyph, bent to the user space.
  func point(_ point: CGPoint) -> CGPoint {
    let point = point.applying(transform)
    let distance = start + point.x / textScale
    let across = y - point.y / textScale
    let onPath = min(max(distance, 0), measure.length)
    guard let (pathPoint, angle) = measure.point(atDistance: onPath) else { return point }
    let radians = angle * .pi / 180
    let (cosine, sine) = (cos(radians), sin(radians))
    let along = distance - onPath
    return CGPoint(
      x: pathPoint.x + cosine * along - sine * across, y: pathPoint.y + sine * along + cosine * across)
  }

  /// A path in the coordinates of the line, with the origin at the origin of the glyph, bent to the user space.
  func bend(_ path: CGPath) -> CGPath {
    let bent = CGMutablePath()
    path.applyWithBlock { element in
      let element = element.pointee
      switch element.type {
      case .moveToPoint:
        bent.move(to: point(element.points[0]))
      case .addLineToPoint:
        bent.addLine(to: point(element.points[0]))
      case .addQuadCurveToPoint:
        bent.addQuadCurve(to: point(element.points[1]), control: point(element.points[0]))
      case .addCurveToPoint:
        bent.addCurve(
          to: point(element.points[2]), control1: point(element.points[0]), control2: point(element.points[1]))
      case .closeSubpath:
        bent.closeSubpath()
      @unknown default:
        break
      }
    }
    return bent
  }
}

/// A path that text is laid out along: the path of a `<textPath>`, the distance along it that the text starts at,
/// and whether the glyphs are bent along it.
struct TextPathLayout {
  let measure: PathMeasure
  let startOffset: CGFloat
  var stretches = false
}

/// Text laid out as the text layout algorithm of SVG 2 lays it out: its characters are shaped and ordered as one
/// line, and then each glyph is placed with the positions that the elements give its character.
///
/// The positions apply in the order of the characters: `x` and `y` move a character and the characters after it to an
/// absolute position, and `dx` and `dy` move them by a distance. A text chunk starts at each character with an
/// absolute position, and is anchored by the `text-anchor` of the element of its first character at the position of
/// that character, with the bounds of its glyphs. The space that spacing adds after the last character of a chunk
/// doesn't count.
///
/// The characters of a `<textPath>` are a chunk of their own, laid out along its path: each glyph is placed at the
/// point of the path where its middle is, turned in the direction of the path, and `dy` and the baselines move it
/// across the path. A glyph whose middle isn't on the path isn't drawn. The characters after the `<textPath>` start a
/// chunk at the end of the path.
struct TextLayout {
  /// The glyphs, in the order of the line.
  let glyphs: [PlacedGlyph]
  /// The metrics of the fonts of each element: the largest ascent, and the largest descent with the leading, in the
  /// coordinates of the line, which the bounds of its glyphs have.
  private let metrics: [Int: (ascent: CGFloat, descent: CGFloat)]
  /// The bounds of text without glyphs, at the current text position.
  private let emptyFrame: CGRect

  /// - Parameters:
  ///   - characters: The characters, with their white space processed and their positions.
  ///   - line: The characters shaped as one line, without the characters that aren't drawn.
  ///   - anchors: The `text-anchor` of each element of the text.
  ///   - baselineOffsets: How far down the glyphs of each element of the text are drawn from the current text
  ///     position, in the user space, for its baselines and its `baseline-shift`.
  ///   - paths: The paths that the characters in `<textPath>` elements are laid out along.
  init(
    characters: [TextCharacter], line: TextLine, anchors: [TextAnchor], baselineOffsets: [CGFloat],
    textScale: CGFloat, paths: [TextPathLayout] = []
  ) {
    struct LineGlyph {
      let font: CTFont
      let glyph: CGGlyph
      let position: CGPoint
      let advance: CGFloat
      let character: Int
    }
    var lineGlyphs = [LineGlyph]()
    var metrics = [Int: (ascent: CGFloat, descent: CGFloat)]()
    for run in Self.glyphRuns(of: line.line) {
      for index in run.glyphs.indices {
        let character = line.characters[run.stringIndices[index]]
        lineGlyphs.append(
          LineGlyph(
            font: run.font, glyph: run.glyphs[index], position: run.positions[index],
            advance: run.advances[index].width, character: character))
        let owner = characters[character].owner
        let current = metrics[owner] ?? (0, 0)
        metrics[owner] = (max(current.ascent, run.ascent), max(current.descent, run.descent))
      }
    }
    self.metrics = metrics
    emptyFrame = CGRect(x: 0, y: baselineOffsets.first ?? 0, width: 0, height: 0)
    // The position of each character in the line, which its first glyph is drawn at, in the user space. A character
    // without a glyph of its own, such as one in a ligature, is where the character before it is.
    var linePositions = [CGFloat?](repeating: nil, count: characters.count)
    for glyph in lineGlyphs {
      let x = glyph.position.x / textScale
      linePositions[glyph.character] = min(linePositions[glyph.character] ?? x, x)
    }
    var previous: CGFloat = 0
    let positions = linePositions.map { position in
      defer { previous = position ?? previous }
      return position ?? previous
    }
    struct Chunk {
      let start: Int
      let anchor: TextAnchor
      let path: Int?
    }
    var chunks = [Chunk]()
    // How far each character is moved along the line, the position of its baseline below the line or across its
    // path, and its chunk.
    var offsets = [CGFloat](repeating: 0, count: characters.count)
    var ys = [CGFloat](repeating: 0, count: characters.count)
    var chunkOfCharacter = [Int](repeating: 0, count: characters.count)
    var offset: CGFloat = 0
    var y: CGFloat = 0
    // How far `dy` has moved the characters of a `<textPath>` across its path.
    var pathY: CGFloat = 0
    for (index, character) in characters.enumerated() {
      let previousPath = index > 0 ? characters[index - 1].path : nil
      let entersPath = character.path != nil && character.path != previousPath
      let leavesPath = previousPath != nil && character.path == nil
      if entersPath {
        // The characters on a path start at its start, and the `y` of a character on a path doesn't apply.
        offset = -positions[index]
        pathY = 0
      } else if leavesPath, let previousPath, let pathEnd = paths[previousPath].measure.end {
        offset = pathEnd.x - positions[index]
        y = pathEnd.y
      }
      if let x = character.x { offset = x - positions[index] }
      offset += character.dx ?? 0
      if character.path == nil {
        y = character.y ?? y
        y += character.dy ?? 0
      } else {
        pathY += character.dy ?? 0
      }
      if chunks.isEmpty || character.startsChunk || entersPath || leavesPath {
        // The characters after a path start at its end, whatever their `text-anchor` is.
        let anchor = leavesPath && !character.startsChunk ? .start : anchors[character.owner]
        chunks.append(Chunk(start: index, anchor: anchor, path: character.path))
      }
      offsets[index] = offset
      ys[index] = (character.path == nil ? y : pathY) + baselineOffsets[character.owner]
      chunkOfCharacter[index] = chunks.count - 1
    }
    // Each chunk is moved so that its anchor is at the position of its first character.
    var bounds = [(start: CGFloat, end: CGFloat)](repeating: (.infinity, -.infinity), count: chunks.count)
    for glyph in lineGlyphs {
      let chunk = chunkOfCharacter[glyph.character]
      let start = glyph.position.x / textScale + offsets[glyph.character]
      let isLast = chunk + 1 < chunks.count ? glyph.character + 1 == chunks[chunk + 1].start : glyph.character + 1 == characters.count
      let end = start + (glyph.advance - (isLast ? line.spacings[glyph.character] : 0)) / textScale
      bounds[chunk] = (min(bounds[chunk].start, start), max(bounds[chunk].end, end))
    }
    let shifts = chunks.indices.map { number -> CGFloat in
      let (start, end) = bounds[number]
      guard start <= end else { return 0 }
      let first = chunks[number].start
      let position = positions[first] + offsets[first]
      return switch chunks[number].anchor {
      case .start: position - start
      case .middle: position - (start + end) / 2
      case .end: position - end
      }
    }
    glyphs = lineGlyphs.compactMap { glyph in
      let character = characters[glyph.character]
      let chunk = chunkOfCharacter[glyph.character]
      let rotation = Self.rotation(of: character.rotate)
      let x = glyph.position.x / textScale + offsets[glyph.character] + shifts[chunk]
      let local = rotation.concatenating(CGAffineTransform(translationX: 0, y: glyph.position.y))
      var placed: PlacedGlyph
      if let pathIndex = chunks[chunk].path {
        let path = paths[pathIndex]
        let middle = path.startOffset + x + glyph.advance / textScale / 2
        guard
          let onPath = Self.place(
            at: middle, on: path, advance: glyph.advance, transform: local, y: ys[glyph.character],
            textScale: textScale)
        else { return nil }
        placed = onPath
      } else {
        placed = PlacedGlyph(
          transform: local.concatenating(CGAffineTransform(scaleX: 1.0 / textScale, y: -1.0 / textScale))
            .concatenating(CGAffineTransform(translationX: x, y: ys[glyph.character])),
          advance: glyph.advance, isStraight: character.rotate == nil)
      }
      placed.owner = character.owner
      placed.font = glyph.font
      placed.glyph = glyph.glyph
      return placed
    }
  }

  /// A glyph placed with its middle at a distance along a path, or `nil` if the middle isn't on the path.
  ///
  /// For a path that's one closed subpath, the glyphs go around it once from the start offset.
  ///
  /// - Parameters:
  ///   - advance: The advance of the glyph, in the coordinates of the line.
  ///   - transform: The transform of the glyph in the coordinates of the line, with the origin at its origin.
  ///   - y: How far across the path the baseline is.
  private static func place(
    at middle: CGFloat, on path: TextPathLayout, advance: CGFloat, transform: CGAffineTransform, y: CGFloat,
    textScale: CGFloat
  ) -> PlacedGlyph? {
    let measure = path.measure
    var distance = middle
    if measure.isClosed {
      guard measure.length > 0, middle - path.startOffset >= 0, middle - path.startOffset <= measure.length
      else { return nil }
      distance = middle.truncatingRemainder(dividingBy: measure.length)
      if distance < 0 { distance += measure.length }
    }
    guard let (point, angle) = measure.point(onPathAt: distance) else { return nil }
    let halfAdvance = advance / textScale / 2
    return PlacedGlyph(
      transform: transform.concatenating(CGAffineTransform(scaleX: 1.0 / textScale, y: -1.0 / textScale))
        .concatenating(CGAffineTransform(translationX: -halfAdvance, y: y))
        .concatenating(CGAffineTransform(rotationAngle: angle * .pi / 180))
        .concatenating(CGAffineTransform(translationX: point.x, y: point.y)),
      advance: advance,
      warp: path.stretches
        ? GlyphWarp(
          measure: measure, transform: transform, start: distance - halfAdvance, y: y, textScale: textScale) : nil)
  }

  /// The bounds of the glyphs of the elements as high as the fonts of the elements, which are larger than the bounds
  /// of their outlines.
  func frame(of owners: Set<Int>? = nil) -> CGRect {
    let boxes = CGMutablePath()
    for glyph in glyphs where owners?.contains(glyph.owner) ?? true {
      let (ascent, descent) = metrics[glyph.owner] ?? (0, 0)
      glyph.add(CGRect(x: 0, y: -descent, width: glyph.advance, height: ascent + descent), to: boxes)
    }
    if boxes.isEmpty { return glyphs.isEmpty && (owners?.contains(0) ?? true) ? emptyFrame : .null }
    return boxes.boundingBoxOfPath
  }

  /// A rotation in degrees of glyphs about their origins, in the coordinates of their line.
  private static func rotation(of degrees: Double?) -> CGAffineTransform {
    // The y-axis of the line points up, so a clockwise rotation in the user space is counterclockwise here.
    degrees.map { CGAffineTransform(rotationAngle: -$0 * .pi / 180) } ?? .identity
  }

  /// The outlines of the glyphs of the elements.
  func path(of owners: Set<Int>? = nil) -> CGPath {
    let path = CGMutablePath()
    for glyph in glyphs where owners?.contains(glyph.owner) ?? true {
      guard let font = glyph.font, let letter = CTFontCreatePathForGlyph(font, glyph.glyph, nil) else { continue }
      glyph.add(letter, to: path)
    }
    return path
  }

  /// The glyph runs of a line: the font, the glyphs, their positions, their advances and the UTF-16 offsets of their
  /// characters, and the ascent and the descent with the leading of the font, in the coordinates of the line.
  static func glyphRuns(
    of line: CTLine
  ) -> [(
    font: CTFont, glyphs: [CGGlyph], positions: [CGPoint], advances: [CGSize], stringIndices: [Int], ascent: CGFloat,
    descent: CGFloat
  )] {
    let glyphRuns = CTLineGetGlyphRuns(line)
    return (0..<CFArrayGetCount(glyphRuns)).map { i in
      let glyphRun = unsafeBitCast(CFArrayGetValueAtIndex(glyphRuns, i), to: CTRun.self)
      let fontPointer = CFDictionaryGetValue(
        CTRunGetAttributes(glyphRun), Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
      let runFont = unsafeBitCast(fontPointer, to: CTFont.self)
      let length = CTRunGetGlyphCount(glyphRun) as Int
      var glyphs = [CGGlyph](repeating: .init(), count: length)
      var positions = [CGPoint](repeating: CGPoint(), count: length)
      var advances = [CGSize](repeating: CGSize(), count: length)
      let range = CFRange(location: 0, length: length)
      CTRunGetGlyphs(glyphRun, range, &glyphs)
      CTRunGetPositions(glyphRun, range, &positions)
      CTRunGetAdvances(glyphRun, range, &advances)
      var stringIndices = [CFIndex](repeating: 0, count: length)
      CTRunGetStringIndices(glyphRun, range, &stringIndices)
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTRunGetTypographicBounds(glyphRun, CFRange(location: 0, length: 0), &ascent, &descent, &leading)
      // The bounds of a line go down by the leading below the descent.
      return (runFont, glyphs, positions, advances, stringIndices, ascent, descent + leading)
    }
  }
}
