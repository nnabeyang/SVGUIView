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
  /// In vertical text, the line is turned clockwise, and the bounds and the lines of `text-decoration` of the glyph
  /// are in it.
  let transform: CGAffineTransform
  /// The advance of the glyph along the line, in the coordinates of the line.
  let advance: CGFloat
  /// The transform of the outline of a glyph that stands upright in vertical text, instead of the transform, or
  /// `nil` if the glyph is in the line.
  var outline: CGAffineTransform? = nil
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
      target.addPath(path, transform: outline ?? transform)
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

/// The length that `textLength` of an element sets for its characters, and how `lengthAdjust` reaches it.
struct TextLengthAdjustment {
  /// The characters of the element and its descendants.
  let characters: Range<Int>
  /// The length along the line, in the user space.
  let length: CGFloat
  /// Whether the glyphs are stretched or squeezed with the spaces between them, as `spacingAndGlyphs` does, instead
  /// of only the spaces.
  let stretchesGlyphs: Bool

  /// The `textLength` and `lengthAdjust` of an element, or `nil` if it has no valid `textLength`, which can't be
  /// negative.
  static func length(attributes: [String: String]) -> (length: SVGLength, stretchesGlyphs: Bool)? {
    guard let length = SVGLength(attributes["textLength"]) else { return nil }
    guard length.nonNegative == length else { return nil }
    let stretches = attributes["lengthAdjust"]?.trimmingCharacters(in: .whitespaces) == "spacingAndGlyphs"
    return (length, stretches)
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
  ///   - directions: The `direction` of each element of the text, which the start and the end of its `text-anchor` are
  ///     in.
  ///   - baselineOffsets: How far down the glyphs of each element of the text are drawn from the current text
  ///     position, in the user space, for its baselines and its `baseline-shift`. In vertical text, the line is
  ///     turned clockwise, and they're how far left.
  ///   - paths: The paths that the characters in `<textPath>` elements are laid out along.
  ///   - isVertical: Whether the text is in a vertical writing mode, where the line goes down: the `y` and `dy` of a
  ///     character are along the line, and its `x` and `dx` across it.
  ///   - uprights: Whether each character stands upright in vertical text, instead of being turned with the line.
  ///   - centralBaselines: How far up the central baseline of the font of each element is, in the user space, which
  ///     the glyphs that stand upright are centered on.
  ///   - lengthAdjustments: The lengths that `textLength` sets, with the descendants before their ancestors.
  init(
    characters: [TextCharacter], line: TextLine, anchors: [TextAnchor], directions: [TextDirection]? = nil,
    baselineOffsets: [CGFloat], textScale: CGFloat, paths: [TextPathLayout] = [], isVertical: Bool = false,
    uprights: [Bool] = [], centralBaselines: [CGFloat] = [], lengthAdjustments: [TextLengthAdjustment] = []
  ) {
    struct LineGlyph {
      let font: CTFont
      let glyph: CGGlyph
      let position: CGPoint
      let advance: CGFloat
      let character: Int
      let isRightToLeft: Bool
      /// Where the glyph starts along the line, and its advance along it, in the coordinates of the line.
      var inlineStart: CGFloat
      var inlineAdvance: CGFloat
      var isUpright = false
    }
    var lineGlyphs = [LineGlyph]()
    var metrics = [Int: (ascent: CGFloat, descent: CGFloat)]()
    for run in Self.glyphRuns(of: line.line) {
      for index in run.glyphs.indices {
        let character = line.characters[run.stringIndices[index]]
        let advance = run.advances[index].width
        lineGlyphs.append(
          LineGlyph(
            font: run.font, glyph: run.glyphs[index], position: run.positions[index], advance: advance,
            character: character, isRightToLeft: run.isRightToLeft, inlineStart: run.positions[index].x,
            inlineAdvance: advance))
        let owner = characters[character].owner
        let current = metrics[owner] ?? (0, 0)
        metrics[owner] = (max(current.ascent, run.ascent), max(current.descent, run.descent))
      }
    }
    if isVertical {
      // Down a vertical line, a glyph that stands upright advances by its vertical advance with the spacing after
      // its character, and the glyphs turned with the line keep their places in the line from where they start.
      var pen: CGFloat = 0
      var lineShift: CGFloat?
      for index in lineGlyphs.indices {
        let glyph = lineGlyphs[index]
        if uprights.indices.contains(glyph.character) && uprights[glyph.character] {
          var verticalGlyph = glyph.glyph
          var advance = CGSize.zero
          CTFontGetAdvancesForGlyphs(glyph.font, .vertical, &verticalGlyph, &advance, 1)
          let isLastOfCharacter = index + 1 == lineGlyphs.count || lineGlyphs[index + 1].character != glyph.character
          lineGlyphs[index].isUpright = true
          lineGlyphs[index].inlineStart = pen
          lineGlyphs[index].inlineAdvance = advance.width + (isLastOfCharacter ? line.spacings[glyph.character] : 0)
          lineShift = nil
        } else {
          let shift = lineShift ?? pen - glyph.position.x
          lineShift = shift
          lineGlyphs[index].inlineStart = glyph.position.x + shift
        }
        pen = lineGlyphs[index].inlineStart + lineGlyphs[index].inlineAdvance
      }
    }
    self.metrics = metrics
    emptyFrame = CGRect(x: 0, y: baselineOffsets.first ?? 0, width: 0, height: 0)
    // The position of each character in the line, in the user space, which is the start of its glyphs: their left
    // end, or their right end in a right-to-left run, as SVG 2 has the advances of right-to-left characters go left.
    // A character without a glyph of its own, such as one in a ligature, is where the character before it is.
    var linePositions = [CGFloat?](repeating: nil, count: characters.count)
    for glyph in lineGlyphs {
      if glyph.isRightToLeft {
        let x = (glyph.inlineStart + glyph.inlineAdvance) / textScale
        linePositions[glyph.character] = max(linePositions[glyph.character] ?? x, x)
      } else {
        let x = glyph.inlineStart / textScale
        linePositions[glyph.character] = min(linePositions[glyph.character] ?? x, x)
      }
    }
    var previous: CGFloat = 0
    let positions = linePositions.map { position in
      defer { previous = position ?? previous }
      return position ?? previous
    }
    struct Chunk {
      let start: Int
      let anchor: TextAnchor
      let direction: TextDirection
      let path: Int?
    }
    var chunks = [Chunk]()
    // How far each character is moved along the line, the position of the line across it or across its path, the
    // position of its baseline below that, and its chunk.
    var offsets = [CGFloat](repeating: 0, count: characters.count)
    var crosses = [CGFloat](repeating: 0, count: characters.count)
    var ys = [CGFloat](repeating: 0, count: characters.count)
    var chunkOfCharacter = [Int](repeating: 0, count: characters.count)
    var offset: CGFloat = 0
    var y: CGFloat = 0
    // How far `dy`, or `dx` in vertical text, has moved the characters of a `<textPath>` across its path.
    var pathY: CGFloat = 0
    for (index, character) in characters.enumerated() {
      let previousPath = index > 0 ? characters[index - 1].path : nil
      let entersPath = character.path != nil && character.path != previousPath
      let leavesPath = previousPath != nil && character.path == nil
      // The positions along the line and across it.
      let (inline, cross) = isVertical ? (character.y, character.x) : (character.x, character.y)
      let (inlineDelta, crossDelta) = isVertical ? (character.dy, character.dx) : (character.dx, character.dy)
      if entersPath {
        // The characters on a path start at its start, and the position across the line of a character on a path
        // doesn't apply.
        offset = -positions[index]
        pathY = 0
      } else if leavesPath, let previousPath, let pathEnd = paths[previousPath].measure.end {
        offset = (isVertical ? pathEnd.y : pathEnd.x) - positions[index]
        y = isVertical ? pathEnd.x : pathEnd.y
      }
      if let inline { offset = inline - positions[index] }
      offset += inlineDelta ?? 0
      if character.path == nil {
        y = cross ?? y
        y += crossDelta ?? 0
      } else {
        pathY += crossDelta ?? 0
      }
      if chunks.isEmpty || character.startsChunk || entersPath || leavesPath {
        // The characters after a path start at its end, whatever their `text-anchor` is.
        let anchor = leavesPath && !character.startsChunk ? .start : anchors[character.owner]
        chunks.append(
          Chunk(start: index, anchor: anchor, direction: directions?[character.owner] ?? .ltr, path: character.path))
      }
      offsets[index] = offset
      crosses[index] = character.path == nil ? y : pathY
      ys[index] = (character.path == nil ? y : pathY) + baselineOffsets[character.owner]
      chunkOfCharacter[index] = chunks.count - 1
    }
    // `textLength` stretches or squeezes the glyphs of a character along the line by its scale, and adds space after
    // it, which its glyphs advance by, so that the lines of `text-decoration` go across the space.
    var scales = [CGFloat](repeating: 1, count: characters.count)
    var addedSpaces = [CGFloat](repeating: 0, count: characters.count)
    if !lengthAdjustments.isEmpty {
      Self.adjustLengths(
        lengthAdjustments, characters: characters,
        glyphs: lineGlyphs.map {
          LengthGlyph(
            character: $0.character, start: $0.inlineStart / textScale, advance: $0.inlineAdvance / textScale,
            isRightToLeft: $0.isRightToLeft)
        }, spacings: line.spacings.map { $0 / textScale }, isVertical: isVertical, offsets: &offsets,
        scales: &scales, addedSpaces: &addedSpaces)
    }
    // Each chunk is moved so that its anchor is at the position of its first character.
    var bounds = [(start: CGFloat, end: CGFloat)](repeating: (.infinity, -.infinity), count: chunks.count)
    for glyph in lineGlyphs {
      let chunk = chunkOfCharacter[glyph.character]
      let scale = scales[glyph.character]
      let start = scale * glyph.inlineStart / textScale + offsets[glyph.character]
      let isLast =
        chunk + 1 < chunks.count
        ? glyph.character + 1 == chunks[chunk + 1].start : glyph.character + 1 == characters.count
      let end = start + scale * (glyph.inlineAdvance - (isLast ? line.spacings[glyph.character] : 0)) / textScale
      bounds[chunk] = (min(bounds[chunk].start, start), max(bounds[chunk].end, end))
    }
    let shifts = chunks.indices.map { number -> CGFloat in
      let (start, end) = bounds[number]
      guard start <= end else { return 0 }
      let first = chunks[number].start
      let position = scales[first] * positions[first] + offsets[first]
      return switch (chunks[number].anchor, chunks[number].direction) {
      case (.start, .ltr), (.end, .rtl): position - start
      case (.middle, _): position - (start + end) / 2
      case (.end, .ltr), (.start, .rtl): position - end
      }
    }
    // The last glyph of each character, which advances by the space that `textLength` adds after the character.
    var lastGlyphs = Set<Int>()
    for (index, glyph) in lineGlyphs.enumerated()
    where index + 1 == lineGlyphs.count || lineGlyphs[index + 1].character != glyph.character {
      lastGlyphs.insert(index)
    }
    glyphs = lineGlyphs.enumerated().compactMap { index, glyph in
      let character = characters[glyph.character]
      let chunk = chunkOfCharacter[glyph.character]
      let rotation = Self.rotation(of: character.rotate)
      let stretch = scales[glyph.character]
      let x = stretch * glyph.inlineStart / textScale + offsets[glyph.character] + shifts[chunk]
      let addedSpace = lastGlyphs.contains(index) ? addedSpaces[glyph.character] * textScale / stretch : 0
      let stretching = CGAffineTransform(scaleX: stretch, y: 1)
      let local = rotation.concatenating(stretching).concatenating(
        CGAffineTransform(translationX: 0, y: glyph.position.y))
      var placed: PlacedGlyph
      let scale = CGAffineTransform(scaleX: 1.0 / textScale, y: -1.0 / textScale)
      if isVertical {
        // The line is turned clockwise, and the baselines move the glyphs left. A glyph that stands upright has its
        // vertical origin on the central baseline of its element at its start, and Core Text gives it a position
        // and a font for the vertical forms, which aren't the ones of the line.
        let baseline = baselineOffsets[character.owner]
        let line = scale.concatenating(CGAffineTransform(translationX: 0, y: baseline))
          .concatenating(CGAffineTransform(rotationAngle: .pi / 2))
        let along = CGAffineTransform(translationX: crosses[glyph.character], y: chunks[chunk].path == nil ? x : 0)
        let frame = (glyph.isUpright ? rotation.concatenating(stretching) : local).concatenating(line).concatenating(
          along)
        var outline: CGAffineTransform?
        if glyph.isUpright {
          var verticalGlyph = glyph.glyph
          var translation = CGSize.zero
          CTFontGetVerticalTranslationsForGlyphs(glyph.font, &verticalGlyph, &translation, 1)
          let central = centralBaselines.indices.contains(character.owner) ? centralBaselines[character.owner] : 0
          let origin = CGPoint(x: central - baseline, y: 0).applying(along)
          // The outline is stretched down the line from its vertical origin.
          outline = rotation.concatenating(scale).concatenating(
            CGAffineTransform(translationX: translation.width / textScale, y: -translation.height / textScale)
          ).concatenating(CGAffineTransform(scaleX: 1, y: stretch)).concatenating(
            CGAffineTransform(translationX: origin.x, y: origin.y))
        }
        if let pathIndex = chunks[chunk].path {
          // On a path, the line goes along the path, which turns it back.
          let path = paths[pathIndex]
          let toPath = CGAffineTransform(rotationAngle: -.pi / 2)
          let middle = path.startOffset + x + stretch * glyph.inlineAdvance / textScale / 2
          guard
            let onPath = Self.place(
              at: middle, on: path, advance: glyph.inlineAdvance, stretch: stretch, frame: frame.concatenating(toPath),
              outline: outline?.concatenating(toPath), textScale: textScale)
          else { return nil }
          placed = onPath
        } else {
          placed = PlacedGlyph(
            transform: frame, advance: glyph.inlineAdvance + addedSpace, outline: outline,
            isStraight: character.rotate == nil)
        }
      } else if let pathIndex = chunks[chunk].path {
        let path = paths[pathIndex]
        let middle = path.startOffset + x + stretch * glyph.advance / textScale / 2
        guard
          let onPath = Self.place(
            at: middle, on: path, advance: glyph.advance, stretch: stretch, transform: local, y: ys[glyph.character],
            textScale: textScale)
        else { return nil }
        placed = onPath
      } else {
        placed = PlacedGlyph(
          transform: local.concatenating(CGAffineTransform(scaleX: 1.0 / textScale, y: -1.0 / textScale))
            .concatenating(CGAffineTransform(translationX: x, y: ys[glyph.character])),
          advance: glyph.advance + addedSpace, isStraight: character.rotate == nil)
      }
      placed.owner = character.owner
      placed.font = glyph.font
      placed.glyph = glyph.glyph
      return placed
    }
  }

  /// A glyph of the line for `textLength`: its character, and where it starts along the line and its advance, in the
  /// user space.
  private struct LengthGlyph {
    let character: Int
    let start: CGFloat
    let advance: CGFloat
    let isRightToLeft: Bool
  }

  /// Applies `textLength` as the text layout algorithm of SVG 2 does, to the elements with the descendants first.
  ///
  /// The characters of an element span the length from the start of the first one to the end of the last one, without
  /// the spacing after it. `spacing` divides the difference from `textLength` among the spaces between the characters,
  /// where the characters of a descendant that `textLength` adjusted already count as one, and `spacingAndGlyphs`
  /// stretches the characters and their glyphs from the start. The characters after the element move by the
  /// difference, with the space after the last character for `spacing`, up to the next one with an absolute position
  /// along the line, as resvg moves them, which SVG 2 leaves to the user agent. A character with an absolute position
  /// along the line stays there, as SVG 2 applies the absolute positions after `textLength`. In right-to-left text,
  /// the characters move to the left.
  ///
  /// - Parameters:
  ///   - spacings: The space that spacing adds after each character, in the user space.
  ///   - offsets: How far each character is moved along the line.
  ///   - scales: How much each character is stretched along the line, from the start of the line.
  ///   - addedSpaces: The space that `spacing` adds after each character.
  private static func adjustLengths(
    _ adjustments: [TextLengthAdjustment], characters: [TextCharacter], glyphs: [LengthGlyph], spacings: [CGFloat],
    isVertical: Bool, offsets: inout [CGFloat], scales: inout [CGFloat], addedSpaces: inout [CGFloat]
  ) {
    var isRightToLeft = [Bool](repeating: false, count: characters.count)
    var hasGlyph = [Bool](repeating: false, count: characters.count)
    for glyph in glyphs {
      isRightToLeft[glyph.character] = glyph.isRightToLeft
      hasGlyph[glyph.character] = true
    }
    // The elements adjusted so far, which their ancestors count as one character each.
    var adjusted = [Range<Int>]()
    for adjustment in adjustments {
      let range = adjustment.characters
      var start = CGFloat.infinity
      var end = -CGFloat.infinity
      for glyph in glyphs where range.contains(glyph.character) {
        let character = glyph.character
        let glyphStart = scales[character] * glyph.start + offsets[character]
        let spacing = character == range.upperBound - 1 ? spacings[character] : 0
        start = min(start, glyphStart)
        end = max(end, glyphStart + scales[character] * (glyph.advance - spacing))
      }
      guard start <= end else { continue }
      let difference = adjustment.length - (end - start)
      // Where each character starts before the adjustment, so that a character with an absolute position along the
      // line stays there, as SVG 2 applies the absolute positions after `textLength`.
      func characterStarts() -> [Int: CGFloat] {
        var starts = [Int: CGFloat]()
        for glyph in glyphs where range.contains(glyph.character) {
          let start = scales[glyph.character] * glyph.start + offsets[glyph.character]
          starts[glyph.character] = min(starts[glyph.character] ?? start, start)
        }
        return starts
      }
      let startsBefore = characterStarts()
      // How far the characters after the element move.
      var following = difference
      if adjustment.stretchesGlyphs {
        let scale = end > start ? adjustment.length / (end - start) : 1
        // The glyphs are stretched from the start of the first character, which is the right end in right-to-left
        // text.
        let origin = isRightToLeft[range.lowerBound] ? end : start
        for character in range {
          scales[character] *= scale
          offsets[character] = scale * offsets[character] + origin * (1 - scale)
          addedSpaces[character] *= scale
        }
      } else {
        // The characters with glyphs, with the characters of each descendant that was adjusted as one.
        let descendants = adjusted.filter { $0 != range && range.lowerBound <= $0.lowerBound && $0.upperBound <= range.upperBound }
        var units = [[Int]]()
        var unitOfDescendant = [Range<Int>: Int]()
        for character in range where hasGlyph[character] {
          if let descendant = descendants.filter({ $0.contains(character) }).max(by: { $0.count < $1.count }) {
            if let unit = unitOfDescendant[descendant] {
              units[unit].append(character)
              continue
            }
            unitOfDescendant[descendant] = units.count
          }
          units.append([character])
        }
        let space = units.count > 1 ? difference / CGFloat(units.count - 1) : 0
        // The procedure of SVG 2 adds the space after the last character too, before the characters after the element,
        // as resvg does.
        if units.count > 1 { following = space * CGFloat(units.count) }
        var shifts = [Int: CGFloat]()
        for (number, unit) in units.enumerated() {
          for character in unit { shifts[character] = space * CGFloat(number) }
          if number + 1 < units.count, let last = unit.last { addedSpaces[last] += space }
        }
        // A character without a glyph of its own moves with the character before it.
        var shift: CGFloat = 0
        for character in range {
          shift = shifts[character] ?? shift
          offsets[character] += isRightToLeft[character] ? -shift : shift
        }
      }
      // A character with an absolute position along the line goes back to it, with the characters after it.
      let startsAfter = characterStarts()
      var back: CGFloat = 0
      for character in range {
        let position = isVertical ? characters[character].y : characters[character].x
        if character > range.lowerBound, position != nil, let before = startsBefore[character],
          let after = startsAfter[character]
        {
          back = after - before
        }
        offsets[character] -= back
      }
      // The characters after the element move by the difference, up to the next absolute position along the line.
      for character in range.upperBound..<characters.count {
        let next = characters[character]
        if (isVertical ? next.y : next.x) != nil || next.path != characters[range.upperBound - 1].path { break }
        // The last absolute position in the element took back what moved the characters before it.
        offsets[character] += (isRightToLeft[character] ? -following : following) - back
      }
      adjusted.append(range)
    }
  }

  /// A glyph placed with its middle at a distance along a path, or `nil` if the middle isn't on the path.
  ///
  /// - Parameters:
  ///   - advance: The advance of the glyph, in the coordinates of the line.
  ///   - stretch: How much the transform stretches the glyph along the line.
  ///   - transform: The transform of the glyph in the coordinates of the line, with the origin at its origin.
  ///   - y: How far across the path the baseline is.
  private static func place(
    at middle: CGFloat, on path: TextPathLayout, advance: CGFloat, stretch: CGFloat, transform: CGAffineTransform,
    y: CGFloat, textScale: CGFloat
  ) -> PlacedGlyph? {
    let measure = path.measure
    guard let distance = distance(of: middle, on: path), let (point, angle) = measure.point(onPathAt: distance)
    else { return nil }
    let halfAdvance = stretch * advance / textScale / 2
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

  /// A glyph placed with its middle at a distance along a path, or `nil` if the middle isn't on the path, from its
  /// transform to the coordinates whose origin is its start on the path, and whose x-axis is in the direction of the
  /// path. Its glyph isn't bent.
  ///
  /// - Parameters:
  ///   - stretch: How much the frame stretches the glyph along the line.
  ///   - outline: The transform of the outline of a glyph that stands upright, or `nil` if it's in the line.
  private static func place(
    at middle: CGFloat, on path: TextPathLayout, advance: CGFloat, stretch: CGFloat, frame: CGAffineTransform,
    outline: CGAffineTransform?, textScale: CGFloat
  ) -> PlacedGlyph? {
    guard let distance = distance(of: middle, on: path), let (point, angle) = path.measure.point(onPathAt: distance)
    else { return nil }
    let along = CGAffineTransform(translationX: -stretch * advance / textScale / 2, y: 0)
      .concatenating(CGAffineTransform(rotationAngle: angle * .pi / 180))
      .concatenating(CGAffineTransform(translationX: point.x, y: point.y))
    return PlacedGlyph(
      transform: frame.concatenating(along), advance: advance, outline: outline?.concatenating(along))
  }

  /// The distance along a path where the middle of a glyph is, or `nil` if the middle isn't on the path.
  ///
  /// For a path that's one closed subpath, the glyphs go around it once from the start offset.
  private static func distance(of middle: CGFloat, on path: TextPathLayout) -> CGFloat? {
    let measure = path.measure
    guard measure.isClosed else { return middle }
    guard measure.length > 0, middle - path.startOffset >= 0, middle - path.startOffset <= measure.length else {
      return nil
    }
    let distance = middle.truncatingRemainder(dividingBy: measure.length)
    return distance < 0 ? distance + measure.length : distance
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
  /// characters, the ascent and the descent with the leading of the font, in the coordinates of the line, and whether
  /// the run goes from right to left.
  static func glyphRuns(
    of line: CTLine
  ) -> [(
    font: CTFont, glyphs: [CGGlyph], positions: [CGPoint], advances: [CGSize], stringIndices: [Int], ascent: CGFloat,
    descent: CGFloat, isRightToLeft: Bool
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
      let isRightToLeft = CTRunGetStatus(glyphRun).contains(.rightToLeft)
      return (runFont, glyphs, positions, advances, stringIndices, ascent, descent + leading, isRightToLeft)
    }
  }
}
