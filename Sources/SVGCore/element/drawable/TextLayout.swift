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
  /// Where each glyph of the line is drawn if the run is laid out along a path, in the order of the glyph runs of
  /// the line, or `nil` if it isn't. A glyph that isn't on the path is `nil`, and isn't drawn. The transform of the
  /// run is then the identity.
  var glyphs: [PlacedGlyph?]? = nil
}

/// A glyph of text laid out along a path.
struct PlacedGlyph {
  /// The transform from the coordinates of the line, with the origin at the origin of the glyph, to the user space.
  let transform: CGAffineTransform
  /// The advance of the glyph, in the coordinates of the line.
  let advance: CGFloat
  /// How the glyph is bent along its path, instead of the transform, or `nil` if it isn't.
  var warp: GlyphWarp? = nil

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

/// Text laid out in runs of characters, with the positions that its elements give them.
///
/// The characters are split into runs where they have positions of their own or belong to another element, and each
/// run is a line of its own. A text chunk starts at each character with an absolute position, and is anchored by the
/// `text-anchor` of the element of its first character with its width. Text of one element without positions of its
/// characters is one run, as one line.
///
/// The characters of a `<textPath>` are a chunk of their own, laid out along its path as the text layout algorithm of
/// SVG 2 does: each glyph is placed at the point of the path where its middle is, turned in the direction of the path,
/// and `dy` and the baselines move it across the path. A glyph whose middle isn't on the path isn't drawn. The
/// characters after the `<textPath>` start a chunk at the end of the path.
struct TextLayout {
  let runs: [PlacedTextRun]

  /// - Parameters:
  ///   - characters: The characters, with their white space processed.
  ///   - anchors: The `text-anchor` of each element of the text.
  ///   - baselineOffsets: How far down the glyphs of each element of the text are drawn from the current text
  ///     position, in the user space, for its baselines and its `baseline-shift`.
  ///   - paths: The paths that the characters in `<textPath>` elements are laid out along.
  ///   - line: Makes the line of a run of characters of an element, with the space after its last character, or
  ///     returns `nil` if they aren't drawn. The space after the last character of a chunk doesn't count in its
  ///     width, which it's anchored with.
  init?(
    characters: [TextCharacter], anchors: [TextAnchor], baselineOffsets: [CGFloat], textScale: CGFloat,
    paths: [TextPathLayout] = [], line: (String, Int) -> (line: CTLine, trailingSpace: CGFloat)?
  ) {
    // The runs, with the index of their first character.
    var starts = [0]
    for index in characters.indices.dropFirst()
    where characters[index].startsRun || characters[index].owner != characters[index - 1].owner
      || characters[index].path != characters[index - 1].path
    {
      starts.append(index)
    }
    struct Run {
      let line: CTLine
      let owner: Int
      /// The width of the line in the coordinates of the line.
      let width: CGFloat
      /// The position of the baseline below the current text position, or across the path for a chunk on a path.
      let y: CGFloat
      /// The distance from the start of the chunk, in the coordinates of the line.
      let offset: CGFloat
      let rotation: Double?
    }
    struct Chunk {
      /// The position of the chunk, or the distance along the path for a chunk on a path.
      let x: CGFloat
      let anchor: TextAnchor
      /// The path that the chunk is laid out along, as an index into the paths.
      let path: Int?
      var width: CGFloat = 0
      var runs = [Run]()
    }
    var chunks = [Chunk]()
    var y: CGFloat = 0
    var x: CGFloat = 0
    // How far `dy` has moved the characters of a `<textPath>` across its path.
    var pathY: CGFloat = 0
    for (number, start) in starts.enumerated() {
      let end = number + 1 < starts.count ? starts[number + 1] : characters.count
      // Text without characters is one empty run of the text itself.
      let first = start < characters.count ? characters[start] : TextCharacter(character: " ", owner: 0)
      let previousPath = start > 0 && start < characters.count ? characters[start - 1].path : nil
      let entersPath = first.path != nil && first.path != previousPath
      let leavesPath = previousPath != nil && first.path == nil
      if entersPath {
        // The characters on a path start at its start, and the `y` of a character on a path doesn't apply.
        x = 0
        pathY = 0
      } else if leavesPath, let previousPath, let pathEnd = paths[previousPath].measure.end {
        x = pathEnd.x
        y = pathEnd.y
      }
      x = first.x ?? x
      x += first.dx ?? 0
      if first.path == nil {
        y = first.y ?? y
        y += first.dy ?? 0
      } else {
        pathY += first.dy ?? 0
      }
      if chunks.isEmpty || first.startsChunk || entersPath || leavesPath {
        // The characters after a path start at its end, whatever their `text-anchor` is.
        let anchor = leavesPath && !first.startsChunk ? .start : anchors[first.owner]
        chunks.append(Chunk(x: x, anchor: anchor, path: first.path))
      }
      guard let (runLine, trailingSpace) = line(String(characters[start..<end].map(\.character)), first.owner)
      else { continue }
      let width = CTLineGetBoundsWithOptions(runLine, CTLineBoundsOptions()).width
      let chunk = chunks.count - 1
      // The offset of the first run of a chunk is 0, so that text without positions is laid out as one line.
      let offset = chunks[chunk].runs.isEmpty ? 0 : (x - chunks[chunk].x) * textScale
      chunks[chunk].runs.append(
        Run(
          line: runLine, owner: first.owner, width: width,
          y: (first.path == nil ? y : pathY) + baselineOffsets[first.owner], offset: offset, rotation: first.rotate))
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
        guard let pathIndex = chunk.path else {
          return PlacedTextRun(
            line: run.line, owner: run.owner, width: run.width,
            transform: CGAffineTransform(translationX: chunk.x, y: run.y)
              .scaledBy(x: 1.0 / textScale, y: -1.0 / textScale)
              .translatedBy(x: anchorOffset + run.offset, y: 0),
            rotation: run.rotation)
        }
        let rotation = Self.rotation(of: run.rotation)
        let path = paths[pathIndex]
        // The distance along the path of the origin of the line.
        let origin = path.startOffset + chunk.x + (anchorOffset + run.offset) / textScale
        let glyphs = Self.glyphRuns(of: run.line).flatMap { glyphRun in
          zip(glyphRun.positions, glyphRun.advances).map { position, advance in
            let middle = origin + (position.x + advance.width / 2) / textScale
            return Self.place(
              at: middle, on: path, advance: advance.width,
              transform: rotation.concatenating(CGAffineTransform(translationX: 0, y: position.y)), y: run.y,
              textScale: textScale)
          }
        }
        return PlacedTextRun(
          line: run.line, owner: run.owner, width: run.width, transform: .identity, rotation: nil, glyphs: glyphs)
      }
    }
    if runs.isEmpty { return nil }
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

  /// The bounds of the lines of the runs of the elements, which are larger than the bounds of their glyphs. A run on
  /// a path has the bounds of the boxes of its glyphs, as high as its line.
  func frame(of owners: Set<Int>? = nil) -> CGRect {
    runs.filter { owners?.contains($0.owner) ?? true }
      .map { run in
        let bounds = CTLineGetBoundsWithOptions(run.line, CTLineBoundsOptions())
        guard let glyphs = run.glyphs else { return bounds.applying(run.transform) }
        let boxes = CGMutablePath()
        for glyph in glyphs.compactMap(\.self) {
          glyph.add(CGRect(x: 0, y: bounds.minY, width: glyph.advance, height: bounds.height), to: boxes)
        }
        return boxes.isEmpty ? CGRect.null : boxes.boundingBoxOfPath
      }
      .reduce(CGRect.null) { $0.union($1) }
  }

  /// The rotation of the glyphs of a run about their origins, in the coordinates of its line.
  static func rotation(of run: PlacedTextRun) -> CGAffineTransform {
    rotation(of: run.rotation)
  }

  /// A rotation in degrees of glyphs about their origins, in the coordinates of their line.
  private static func rotation(of degrees: Double?) -> CGAffineTransform {
    // The y-axis of the line points up, so a clockwise rotation in the user space is counterclockwise here.
    degrees.map { CGAffineTransform(rotationAngle: -$0 * .pi / 180) } ?? .identity
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
    var number = 0
    for glyphRun in glyphRuns(of: run.line) {
      for (glyph, position) in zip(glyphRun.glyphs, glyphRun.positions) {
        defer { number += 1 }
        if let glyphs = run.glyphs {
          guard let placed = glyphs[number], let letter = CTFontCreatePathForGlyph(glyphRun.font, glyph, nil)
          else { continue }
          placed.add(letter, to: letters)
        } else {
          guard let letter = CTFontCreatePathForGlyph(glyphRun.font, glyph, nil) else { continue }
          letters.addPath(
            letter, transform: rotation.concatenating(CGAffineTransform(translationX: position.x, y: position.y)))
        }
      }
    }
    return letters
  }

  /// The glyph runs of a line: the font, the glyphs, their positions and their advances, in the coordinates of the
  /// line.
  static func glyphRuns(
    of line: CTLine
  ) -> [(font: CTFont, glyphs: [CGGlyph], positions: [CGPoint], advances: [CGSize])] {
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
      return (runFont, glyphs, positions, advances)
    }
  }
}
