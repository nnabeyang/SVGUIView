import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

@Suite("Render tree")
struct RenderTreeBuilderTests {
  /// The render tree of a document rendered into a rectangle of 20 by 20 at a scale of 1, at the time in seconds.
  ///
  /// - Parameter attributes: More attributes of the root `<svg>` element.
  private func renderTree(_ content: String, at time: Double = 0, attributes: String = "") async throws -> RenderTree {
    let svg =
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" "# + attributes + ">" + content + "</svg>"
    let base = SVGParser.parse(data: Data(svg.utf8)).at(time: time)
    let builder = RenderTreeBuilder(base: base, viewPort: CGRect(x: 0, y: 0, width: 20, height: 20), scale: 1)
    return try #require(
      await builder.build(
        fit: ContentFit(
          preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false,
          scales: true)))
  }

  /// The children of the root `<svg>` element.
  private func children(of tree: RenderTree) throws -> [RenderNode] {
    guard case .viewport(let viewport) = tree.root else {
      Issue.record("The root isn't a viewport")
      return []
    }
    return try #require(viewport.content).children
  }

  private func use(_ node: RenderNode) throws -> UseNode {
    guard case .use(let use) = node else { throw NodeError.unexpected(node) }
    return use
  }

  private func shape(_ node: RenderNode?) throws -> ShapeNode {
    guard case .shape(let shape) = node else { throw NodeError.unexpected(node) }
    return shape
  }

  private enum NodeError: Error {
    case unexpected(RenderNode?)
  }

  @Test("each use element makes its own copy of the content, which keeps the identity of the element")
  func useInstances() async throws {
    let tree = try await renderTree(
      ##"<defs><rect id="r" width="10" height="10"/></defs><use href="#r"/><use href="#r" x="10"/>"##)
    let nodes = try children(of: tree)
    #expect(nodes.count == 3)
    let first = try use(nodes[1])
    let second = try use(nodes[2])
    let firstShape = try shape(try #require(first.instance).content)
    let secondShape = try shape(try #require(second.instance).content)
    #expect(firstShape.id.element == secondShape.id.element)
    #expect(firstShape.id.instance == [first.id.element])
    #expect(secondShape.id.instance == [second.id.element])
    #expect(firstShape.id != secondShape.id)
    #expect(try #require(second.instance).translation == CGAffineTransform(translationX: 10, y: 0))
  }

  @Test("a use element that references an element that contains it shows nothing")
  func useCycle() async throws {
    let tree = try await renderTree(##"<g id="g"><use href="#g"/></g>"##)
    guard case .group(let group) = try children(of: tree).first else {
      Issue.record("The first child isn't a group")
      return
    }
    #expect(try use(try #require(group.children.first)).instance == nil)
  }

  @Test("the SMIL animations of an element apply to its copies in use elements")
  func animatedUseInstances() async throws {
    let tree = try await renderTree(
      ##"<defs><rect id="r" width="10" height="10"><set attributeName="opacity" to="0.5"/></rect></defs><use href="#r"/>"##,
      at: 1)
    let copy = try use(try #require(try children(of: tree).last))
    #expect(try shape(try #require(copy.instance).content).opacity == 0.5)
  }

  @Test("a gradient takes the stops of the gradient that it references")
  func gradientReference() async throws {
    let tree = try await renderTree(
      ##"""
      <linearGradient id="a"><stop offset="0" stop-color="lime"/><stop offset="1" stop-color="blue"/></linearGradient>
      <linearGradient id="b" href="#a" x2="0" y2="1"/>
      <rect width="20" height="20" fill="url(#b)"/>
      """##)
    let rect = try shape(try children(of: tree).last)
    guard case .vector(.gradient(.linear(let gradient)), _, _) = rect.content else {
      Issue.record("The rectangle isn't filled with a linear gradient")
      return
    }
    #expect(gradient.colors.count == 2)
    #expect(gradient.locations == [0, 1])
    #expect(gradient.x2 == 0)
    #expect(gradient.y2 == 1)
  }

  /// Gradients, and the transform of the gradient that the last rectangle is filled with.
  private static let gradientTransforms: [(String, CGAffineTransform)] = [
    (
      #"<linearGradient id="g" gradientTransform="translate(5 10) scale(2)"><stop stop-color="lime"/></linearGradient>"#,
      CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 5, ty: 10)
    ),
    (
      #"<radialGradient id="g" gradientTransform="translate(5, 10)"><stop stop-color="lime"/></radialGradient>"#,
      CGAffineTransform(translationX: 5, y: 10)
    ),
    // A gradient takes the transform of the gradient that it references, of either kind, if it has none.
    (
      ##"""
      <radialGradient id="a" gradientTransform="translate(5)"><stop stop-color="lime"/></radialGradient>
      <linearGradient id="g" href="#a"/>
      """##,
      CGAffineTransform(translationX: 5, y: 0)
    ),
    (
      ##"""
      <linearGradient id="a" gradientTransform="translate(5)"><stop stop-color="lime"/></linearGradient>
      <linearGradient id="g" href="#a" gradientTransform="scale(3)"/>
      """##,
      CGAffineTransform(scaleX: 3, y: 3)
    ),
    (#"<linearGradient id="g" gradientTransform="("><stop stop-color="lime"/></linearGradient>"#, .identity),
  ]

  @Test(
    "a gradient transform is the transform of the gradient, and is ignored if it isn't valid",
    arguments: gradientTransforms)
  func gradientTransform(gradients: String, transform: CGAffineTransform) async throws {
    let tree = try await renderTree(gradients + #"<rect width="20" height="20" fill="url(#g)"/>"#)
    let rect = try shape(try children(of: tree).last)
    switch rect.content {
    case .vector(.gradient(.linear(let gradient)), _, _):
      #expect(gradient.transform == transform)
    case .vector(.gradient(.radial(let gradient)), _, _):
      #expect(gradient.transform == transform)
    default:
      Issue.record("The rectangle isn't filled with a gradient")
    }
  }

  @Test("lengths in percentages and text scale with the viewBox of a nested svg element")
  func nestedViewBox() async throws {
    let tree = try await renderTree(
      #"<svg width="20" height="20" viewBox="0 0 10 10"><rect width="50%" height="50%"/></svg>"#)
    guard case .viewport(let nested) = try children(of: tree).first else {
      Issue.record("The first child isn't a viewport")
      return
    }
    let rect = try shape(try #require(nested.content).children.first)
    #expect(try #require(rect.geometry).frame == CGRect(x: 0, y: 0, width: 5, height: 5))
  }

  /// Text, and text with the same bounds whose white space is drawn as it's written.
  private static let textWhiteSpaces: [(String, String)] = [
    ("<text x=\"10\" y=\"10\" font-size=\"4\">\n    A\n    B\n  </text>", "A B"),
    (#"<text x="10" y="10" font-size="4" xml:space="preserve">  A\#nB  </text>"#, "  A B  "),
    (#"<g xml:space="preserve"><text x="10" y="10" font-size="4">  A  B</text></g>"#, "  A  B"),
    (#"<g xml:space="preserve"><text x="10" y="10" font-size="4" xml:space="default">  A  B</text></g>"#, "A B"),
    (#"<text x="10" y="10" font-size="4" xml:space="preserve" white-space="normal">  A  </text>"#, "A"),
    (#"<style>text { white-space: normal }</style><text x="10" y="10" font-size="4" xml:space="preserve"> A </text>"#, "A"),
  ]

  @Test("text is drawn with its white space processed, as white-space or xml:space says", arguments: textWhiteSpaces)
  func textWhiteSpace(text: String, drawn: String) async throws {
    let tree = try await renderTree(
      text + #"<text x="10" y="10" font-size="4" style="white-space: pre">"# + drawn + "</text>")
    let nodes = try children(of: tree).flatMap { node -> [RenderNode] in
      if case .group(let group) = node { group.children } else { [node] }
    }
    let texts = try nodes.compactMap { node -> Geometry? in
      if case .shape = node { try shape(node).geometry } else { nil }
    }
    try #require(texts.count == 2)
    #expect(texts[1].frame.width > 0)
    #expect(abs(texts[0].frame.minX - texts[1].frame.minX) < 0.001)
    #expect(abs(texts[0].frame.width - texts[1].frame.width) < 0.001)
  }

  @Test("text with line breaks and indents around it is anchored at its end at x")
  func textAnchorWithWhiteSpace() async throws {
    let tree = try await renderTree("<text x=\"10\" y=\"10\" font-size=\"4\" text-anchor=\"end\">\n    Text\n  </text>")
    let text = try #require(try shape(try children(of: tree).first).geometry)
    #expect(text.frame.width > 0)
    #expect(abs(text.frame.maxX - 10) < 0.001)
  }

  /// Text with positions of its characters, and texts that draw the same glyphs.
  private static let characterPositions: [(String, String)] = [
    (#"<text x="2 8 14" y="10">abc</text>"#, #"<text x="2" y="10">a</text><text x="8" y="10">b</text><text x="14" y="10">c</text>"#),
    (#"<text x="2 8" y="10 14">ab</text>"#, #"<text x="2" y="10">a</text><text x="8" y="14">b</text>"#),
    // The characters after the list follow the last character with a position, on one line.
    (#"<text x="2 8" y="10">abc</text>"#, #"<text x="2" y="10">a</text><text x="8" y="10">bc</text>"#),
    (#"<text x="2" dx="3" y="10" dy="2">ab</text>"#, #"<text x="5" y="12">ab</text>"#),
    (#"<text x="2 8" dx="1, 1" y="10">ab</text>"#, #"<text x="3 9" y="10">ab</text>"#),
    // A list with a value that isn't a length is ignored.
    (#"<text x="2 a" y="10">ab</text>"#, #"<text y="10">ab</text>"#),
    // The last rotation applies to the characters after the list.
    (#"<text x="2" y="10" rotate="0 180">TTT</text>"#, #"<text x="2" y="10" rotate="0 180 180">TTT</text>"#),
    // Each text chunk is anchored at its absolute position.
    (
      #"<text x="10 20" y="10" text-anchor="end">ab</text>"#,
      #"<text x="10" y="10" text-anchor="end">a</text><text x="20" y="10" text-anchor="end">b</text>"#
    ),
  ]

  @Test("x, y, dx, dy and rotate place the characters of text", arguments: characterPositions)
  func textCharacterPositions(text: String, same: String) async throws {
    func glyphBounds(_ content: String) async throws -> CGRect {
      let tree = try await renderTree(#"<g font-size="4">"# + content + "</g>")
      guard case .group(let group) = try children(of: tree).first else { throw NodeError.unexpected(nil) }
      return try group.children.map { try #require(try shape($0).geometry).path.cgPath.boundingBoxOfPath }
        .reduce(CGRect.null) { $0.union($1) }
    }
    let actual = try await glyphBounds(text)
    let expected = try await glyphBounds(same)
    #expect(!actual.isEmpty)
    for (a, e) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.maxX, expected.maxX), (actual.maxY, expected.maxY)] {
      #expect(abs(a - e) < 0.001, "\(actual) isn't \(expected)")
    }
  }

  @Test("rotate turns each glyph about its origin, clockwise")
  func textRotation() async throws {
    let tree = try await renderTree(#"<text x="10" y="10" font-size="4" rotate="180">T</text>"#)
    let glyphs = try #require(try shape(try children(of: tree).first).geometry).path.cgPath.boundingBoxOfPath
    // Turned half a turn about (10, 10), the letter is left of x and below the baseline.
    #expect(glyphs.maxX <= 10.001 && glyphs.minX < 10)
    #expect(glyphs.minY >= 9.999 && glyphs.maxY > 10)
  }

  /// The shapes of the nodes and their descendants, in order.
  private func shapes(of nodes: [RenderNode]) -> [ShapeNode] {
    nodes.flatMap { node -> [ShapeNode] in
      switch node {
      case .shape(let shape): [shape]
      case .group(let group): shapes(of: group.children)
      default: []
      }
    }
  }

  /// The color that a shape is filled with, or `nil` if it isn't filled with a color.
  private func fillColor(of shape: ShapeNode) -> CGColor? {
    if case .vector(.color(let color), _, _) = shape.content { color } else { nil }
  }

  @Test("a tspan is a shape of its own in the group of its text, with its fill and the fill that it inherits")
  func tspanShapes() async throws {
    let tree = try await renderTree(
      #"<text x="2" y="10" font-size="4" fill="red">a<tspan fill="lime">b<tspan>c</tspan></tspan>d</text>"#)
    guard case .group(let text) = try children(of: tree).first else {
      Issue.record("The text isn't a group")
      return
    }
    let shapes = shapes(of: text.children)
    #expect(shapes.count == 3)
    #expect(Set(shapes.map(\.id.element)).count == 3)
    #expect(shapes.map { fillColor(of: $0)?.components ?? [] } == [[1, 0, 0, 1], [0, 1, 0, 1], [0, 1, 0, 1]])
    // The shapes have the bounds of the whole text.
    #expect(Set(shapes.map { $0.geometry?.frame.width ?? 0 }).count == 1)
  }

  /// Text with tspans, and texts that draw the same glyphs.
  private static let tspanTexts: [(String, String)] = [
    // White space collapses across the elements.
    (#"<text x="2" y="10">a <tspan> b </tspan> c</text>"#, #"<text x="2" y="10">a b c</text>"#),
    (#"<text x="2" y="10">a<tspan x="8">b</tspan></text>"#, #"<text x="2" y="10">a</text><text x="8" y="10">b</text>"#),
    (
      #"<text x="2 8 14" y="10">a<tspan dy="3">b</tspan>c</text>"#,
      #"<text x="2" y="10">a</text><text x="8" y="13">b</text><text x="14" y="13">c</text>"#
    ),
    // The positions of a tspan win over the positions of its text.
    (#"<text x="2 8" y="10">a<tspan x="20">b</tspan></text>"#, #"<text x="2" y="10">a</text><text x="20" y="10">b</text>"#),
    (#"<text x="2" y="10">a<tspan display="none">b</tspan>c</text>"#, #"<text x="2" y="10">ac</text>"#),
    (
      #"<text x="2 8" y="10">a<tspan font-size="8">b</tspan></text>"#,
      #"<text x="2" y="10">a</text><text x="8" y="10" font-size="8">b</text>"#
    ),
    // The element of the first character of a chunk anchors it.
    (
      #"<text x="10" y="10"><tspan text-anchor="end">a</tspan>b</text>"#,
      #"<text x="10" y="10" text-anchor="end">ab</text>"#
    ),
  ]

  @Test("tspans place their characters, and the white space of text collapses across them", arguments: tspanTexts)
  func tspanPositions(text: String, same: String) async throws {
    func glyphBounds(_ content: String) async throws -> CGRect {
      let tree = try await renderTree(#"<g font-size="4">"# + content + "</g>")
      return try shapes(of: children(of: tree)).map { try #require($0.geometry).path.cgPath.boundingBoxOfPath }
        .reduce(CGRect.null) { $0.union($1) }
    }
    let actual = try await glyphBounds(text)
    let expected = try await glyphBounds(same)
    #expect(!actual.isEmpty)
    for (a, e) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.maxX, expected.maxX), (actual.maxY, expected.maxY)] {
      #expect(abs(a - e) < 0.001, "\(actual) isn't \(expected)")
    }
  }

  @Test("a tspan outside text isn't rendered, and a hidden tspan takes its place without painting")
  func tspanOutsideTextAndHidden() async throws {
    let outside = try await renderTree(#"<g><tspan x="2" y="10">a</tspan></g>"#)
    guard case .group(let group) = try children(of: outside).first else {
      Issue.record("The g isn't a group")
      return
    }
    #expect(group.children.isEmpty)
    let hidden = try await renderTree(#"<text x="2" y="10" font-size="4">a<tspan visibility="hidden">b</tspan>c</text>"#)
    let shapes = shapes(of: try children(of: hidden))
    #expect(shapes.count == 2)
    #expect(shapes.map { $0.content == nil } == [false, true])
  }

  @Test("the animations of a tspan apply to its glyphs")
  func tspanAnimation() async throws {
    let tree = try await renderTree(
      #"<text x="2" y="10" font-size="4">a<tspan fill="red">b<set attributeName="fill" to="lime" begin="1s"/></tspan></text>"#,
      at: 2)
    let shapes = shapes(of: try children(of: tree))
    #expect(shapes.last.flatMap(fillColor(of:))?.components == [0, 1, 0, 1])
  }

  /// Text with spacings, and text with the same glyphs placed by `dx`.
  private static let spacedTexts: [(String, String)] = [
    (#"<text x="2" y="10" letter-spacing="2">ab</text>"#, #"<text x="2" y="10" dx="0 2">ab</text>"#),
    (#"<text x="2" y="10" letter-spacing="50%">ab</text>"#, #"<text x="2" y="10" dx="0 2">ab</text>"#),
    (#"<text x="2" y="10" word-spacing="3">a b</text>"#, #"<text x="2" y="10" dx="0 0 3">a b</text>"#),
    (#"<text x="2" y="10">a<tspan letter-spacing="2">bc</tspan></text>"#, #"<text x="2" y="10" dx="0 0 2">abc</text>"#),
    // The space after the last character doesn't count in the width that text-anchor anchors.
    (
      #"<text x="10" y="10" text-anchor="end" letter-spacing="2">ab</text>"#,
      #"<text x="10" y="10" text-anchor="end" dx="0 2">ab</text>"#
    ),
  ]

  @Test("letter-spacing and word-spacing add space after characters and spaces", arguments: spacedTexts)
  func textSpacing(text: String, same: String) async throws {
    func glyphBounds(_ content: String) async throws -> CGRect {
      let tree = try await renderTree(#"<g font-size="4">"# + content + "</g>")
      return try shapes(of: children(of: tree)).map { try #require($0.geometry).path.cgPath.boundingBoxOfPath }
        .reduce(CGRect.null) { $0.union($1) }
    }
    let actual = try await glyphBounds(text)
    let expected = try await glyphBounds(same)
    #expect(!actual.isEmpty)
    for (a, e) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.maxX, expected.maxX), (actual.maxY, expected.maxY)] {
      #expect(abs(a - e) < 0.01, "\(actual) isn't \(expected)")
    }
  }

  @Test("a spacing of 0 keeps the kerning of the font")
  func zeroSpacing() async throws {
    func glyphBounds(_ content: String) async throws -> CGRect {
      let tree = try await renderTree(#"<g font-size="4">"# + content + "</g>")
      return try #require(
        try shape(
          try children(of: tree).first.flatMap { node in
            if case .group(let group) = node { group.children.first } else { nil }
          }
        ).geometry
      ).path.cgPath.boundingBoxOfPath
    }
    let spaced = try await glyphBounds(#"<text x="2" y="10" letter-spacing="0" word-spacing="normal">AVA</text>"#)
    let plain = try await glyphBounds(#"<text x="2" y="10">AVA</text>"#)
    #expect(spaced == plain)
  }

  /// The bounds of the outlines of a shape.
  private func bounds(of shape: ShapeNode) throws -> CGRect {
    try #require(shape.geometry).path.cgPath.boundingBoxOfPath
  }

  @Test("an underline goes under the glyphs, and a text with one is one shape")
  func underline() async throws {
    let plain = try shape(try children(of: try await renderTree(#"<text x="2" y="10" font-size="4">ab</text>"#)).first)
    let decorated = try shape(
      try children(
        of: try await renderTree(
          #"<text x="2" y="10" font-size="4" text-decoration="underline">ab</text>"#)
      ).first)
    // The glyphs go a little below the baseline, and the underline further.
    #expect(try bounds(of: decorated).maxY > bounds(of: plain).maxY + 0.2)
    #expect(try bounds(of: decorated).minX <= bounds(of: plain).minX)
  }

  @Test("a line declared around text is drawn with the paints of the text, under the glyphs of its tspans")
  func decorationAroundText() async throws {
    let tree = try await renderTree(
      #"<g text-decoration="underline" fill="red"><text x="2" y="10" font-size="4" fill="lime">a"#
        + #"<tspan fill="blue">bcd</tspan></text></g>"#)
    let shapes = shapes(of: try children(of: tree))
    try #require(shapes.count == 2)
    #expect(shapes.map { fillColor(of: $0)?.components ?? [] } == [[0, 1, 0, 1], [0, 0, 1, 1]])
    // The underline of the text goes under the glyphs of the tspan too.
    #expect(try bounds(of: shapes[0]).maxX >= bounds(of: shapes[1]).maxX - 0.5)
    #expect(try bounds(of: shapes[0]).maxY > bounds(of: shapes[1]).maxY + 0.2)
  }

  @Test("a line through text is drawn after all the glyphs, with the paints of the element that declares it")
  func lineThrough() async throws {
    let tree = try await renderTree(
      #"<text x="2" y="10" font-size="4">a<tspan fill="blue" text-decoration="line-through">b</tspan>c</text>"#)
    let shapes = shapes(of: try children(of: tree))
    try #require(shapes.count == 3)
    #expect(shapes[2].id == shapes[1].id)
    #expect(fillColor(of: shapes[2])?.components == [0, 0, 1, 1])
    // The line is above the baseline, over the glyph.
    let line = try bounds(of: shapes[2])
    let glyph = try bounds(of: shapes[1])
    #expect(line.maxY < 10 && line.minY > glyph.minY)
  }

  @Test("an underline follows the characters that dy moves")
  func underlineFollowsPositions() async throws {
    let tree = try await renderTree(
      #"<text x="2" y="10" font-size="4" text-decoration="underline">a<tspan dy="5">b</tspan></text>"#)
    let shapes = shapes(of: try children(of: tree))
    try #require(shapes.count == 2)
    // The underline of the text goes under the glyph that dy moves down by 5.
    #expect(try bounds(of: shapes[0]).maxY > bounds(of: shapes[1]).maxY + 0.2)
    #expect(try bounds(of: shapes[1]).minY > 10)
  }

  /// Text with baselines and shifts, and text with the same glyphs placed by `dy`.
  private static let shiftedTexts: [(String, String)] = [
    (
      #"<text x="2" y="10">a<tspan baseline-shift="5">b</tspan>c</text>"#,
      #"<text x="2" y="10">a<tspan dy="-5">b</tspan><tspan dy="5">c</tspan></text>"#
    ),
    (#"<text x="2" y="10">a<tspan baseline-shift="50%">b</tspan></text>"#, #"<text x="2" y="10">a<tspan dy="-2">b</tspan></text>"#),
    // The shifts of nested tspans add up.
    (
      #"<text x="2" y="10">a<tspan baseline-shift="2">b<tspan baseline-shift="3">c</tspan></tspan></text>"#,
      #"<text x="2" y="10">a<tspan dy="-2">b</tspan><tspan dy="-3">c</tspan></text>"#
    ),
    // The shift of text itself and an invalid shift don't move the glyphs.
    (#"<text x="2" y="10" baseline-shift="5">ab</text>"#, #"<text x="2" y="10">ab</text>"#),
    (#"<text x="2" y="10">a<tspan baseline-shift="qwe">b</tspan></text>"#, #"<text x="2" y="10">ab</text>"#),
    // alignment-baseline aligns only the characters of its element.
    (
      #"<text x="2" y="10">a<tspan alignment-baseline="text-before-edge">b</tspan>c</text>"#,
      #"<text x="2" y="10">a<tspan dominant-baseline="text-before-edge">b</tspan>c</text>"#
    ),
    (
      #"<text x="2" y="10" dominant-baseline="middle">a<tspan dominant-baseline="no-change">b</tspan></text>"#,
      #"<text x="2" y="10" dominant-baseline="middle">ab</text>"#
    ),
  ]

  @Test("baseline-shift moves the glyphs of tspans up, and baselines align only the glyphs of their elements", arguments: shiftedTexts)
  func baselineShift(text: String, same: String) async throws {
    func glyphBounds(_ content: String) async throws -> CGRect {
      let tree = try await renderTree(#"<g font-size="4">"# + content + "</g>")
      return try shapes(of: children(of: tree)).map { try #require($0.geometry).path.cgPath.boundingBoxOfPath }
        .reduce(CGRect.null) { $0.union($1) }
    }
    let actual = try await glyphBounds(text)
    let expected = try await glyphBounds(same)
    #expect(!actual.isEmpty)
    for (a, e) in [(actual.minX, expected.minX), (actual.minY, expected.minY), (actual.maxX, expected.maxX), (actual.maxY, expected.maxY)] {
      #expect(abs(a - e) < 0.01, "\(actual) isn't \(expected)")
    }
  }

  @Test("text aligned by its text-before-edge is below y, and by its text-after-edge above the alphabetic baseline")
  func textEdges() async throws {
    func glyphBounds(_ baseline: String) async throws -> CGRect {
      try bounds(
        of: try shape(
          try children(
            of: try await renderTree(
              #"<text x="2" y="10" font-size="4" dominant-baseline="\#(baseline)">bg</text>"#)
          ).first))
    }
    // The ascent of the font is above the tops of the glyphs.
    #expect(try await glyphBounds("text-before-edge").minY >= 10 - 0.01)
    // The glyphs go up by the descent of the font, which a glyph can go further down than.
    #expect(try await glyphBounds("text-after-edge").maxY < glyphBounds("alphabetic").maxY - 0.2)
  }

  /// Text, and the part of its width that its `text-anchor` moves it left by.
  private static let textAnchors: [(String, CGFloat)] = [
    (#"<text x="10" y="10" font-size="4">Text</text>"#, 0),
    (#"<text x="10" y="10" font-size="4" text-anchor="middle">Text</text>"#, 0.5),
    (#"<text x="10" y="10" font-size="4" text-anchor="end">Text</text>"#, 1),
    (#"<text x="10" y="10" font-size="4" style="text-anchor: end">Text</text>"#, 1),
    (#"<g text-anchor="end"><text x="10" y="10" font-size="4">Text</text></g>"#, 1),
  ]

  @Test("text-anchor moves the bounds and the glyphs of text so that its start, middle or end is at x", arguments: textAnchors)
  func textAnchor(text: String, part: CGFloat) async throws {
    let tree = try await renderTree(#"<text x="10" y="10" font-size="4">Text</text>"# + text)
    let start = try #require(try shape(try children(of: tree).first).geometry)
    var anchored = try children(of: tree).last
    if case .group(let group) = anchored {
      anchored = group.children.first
    }
    let geometry = try #require(try shape(anchored).geometry)
    let offset = -start.frame.width * part
    #expect(start.frame.width > 0)
    #expect(abs(start.frame.minX - 10) < 0.001)
    #expect(abs(geometry.frame.minX - (10 + offset)) < 0.001)
    #expect(abs(geometry.frame.width - start.frame.width) < 0.001)
    let startGlyphs = start.path.cgPath.boundingBoxOfPath
    let glyphs = geometry.path.cgPath.boundingBoxOfPath
    #expect(abs(glyphs.minX - (startGlyphs.minX + offset)) < 0.001)
    #expect(abs(glyphs.width - startGlyphs.width) < 0.001)
  }

  @Test("a group with a clip path finds its bounds without the shapes of patterns and masks")
  func clippedGroupWithPattern() async throws {
    let tree = try await renderTree(
      #"""
      <clipPath id="c"><rect width="10" height="10"/></clipPath>
      <g clip-path="url(#c)">
        <g><pattern id="p" width="2" height="2"/><mask id="m"/></g>
        <rect x="5" y="5" width="10" height="10"/>
      </g>
      """#)
    guard case .group(let group) = try children(of: tree).last else {
      Issue.record("The last child isn't a group")
      return
    }
    #expect(try #require(group.clip).frame == CGRect(x: 0, y: 0, width: 15, height: 15))
  }

  @Test("a clip path that a shape in it references again clips nothing more")
  func clipPathCycle() async throws {
    let tree = try await renderTree(
      ##"""
      <clipPath id="c"><rect width="10" height="10" clip-path="url(#c)"/></clipPath>
      <rect width="20" height="20" clip-path="url(#c)"/>
      """##)
    let clip = try #require(try shape(try children(of: tree).last).clip)
    #expect(clip.frame == CGRect(x: 0, y: 0, width: 20, height: 20))
    #expect(clip.shapes.count == 1)
    #expect(clip.shapes.first?.clip == nil)
  }

  @Test("a clip path of an element whose bounds have no pixel clips nothing")
  func clipPathOfEmptyBounds() async throws {
    let tree = try await renderTree(
      ##"<clipPath id="c"><rect width="10" height="10"/></clipPath><g clip-path="url(#c)"/>"##)
    guard case .group(let group) = try children(of: tree).last else {
      Issue.record("The last child isn't a group")
      return
    }
    #expect(group.clip == nil)
  }

  @Test("a group of use elements has the bounds of the elements that they reference, also in its clip path")
  func clippedGroupOfUseElements() async throws {
    let tree = try await renderTree(
      ##"""
      <defs><rect id="r" x="2" y="3" width="10" height="10"/></defs>
      <clipPath id="c"><use href="#r"/></clipPath>
      <g clip-path="url(#c)"><use href="#r" x="1"/></g>
      """##)
    guard case .group(let group) = try children(of: tree).last else {
      Issue.record("The last child isn't a group")
      return
    }
    let clip = try #require(group.clip)
    #expect(clip.frame == CGRect(x: 3, y: 3, width: 10, height: 10))
    #expect(clip.shapes.count == 1)
  }

  @Test("a use element in a clip path takes the clip rule of the element that it references")
  func clipRuleOfUseElement() async throws {
    let tree = try await renderTree(
      ##"""
      <defs>
        <path id="p" d="M0 0h10v10h-10z" clip-rule="evenodd"/>
        <path id="q" d="M0 0h10v10h-10z"/>
      </defs>
      <clipPath id="c">
        <use href="#p"/>
        <use href="#q" clip-rule="evenodd"/>
        <use href="#q"/>
      </clipPath>
      <rect width="20" height="20" clip-path="url(#c)"/>
      """##)
    let clip = try #require(try shape(try children(of: tree).last).clip)
    #expect(clip.shapes.map(\.fillRule) == [.eoFill, .eoFill, .fill])
  }

  @Test("a mask covers its region, and a pattern in it paints, stopping a cycle of patterns")
  func maskWithPattern() async throws {
    let tree = try await renderTree(
      ##"""
      <pattern id="p" width="1" height="1"><rect width="1" height="1" fill="url(#p)"/></pattern>
      <mask id="m"><rect width="20" height="20" fill="url(#p)"/></mask>
      <rect width="10" height="10" mask="url(#m)"/>
      """##)
    guard case .mask(let mask) = try shape(try children(of: tree).last).mask else {
      Issue.record("The rectangle isn't masked")
      return
    }
    #expect(mask.frame == CGRect(x: 0, y: 0, width: 10, height: 10))
    #expect(mask.region == CGRect(x: -2, y: -2, width: 24, height: 24))
    guard case .vector(.pattern(let paint), _, _) = try #require(mask.contents.first).fill else {
      Issue.record("The content of the mask isn't filled with a pattern")
      return
    }
    // The rectangle in the tile references the pattern again, which paints black.
    guard case .vector(.color(let color), _, _) = try shape(try #require(paint).content.first).content else {
      Issue.record("The content of the pattern isn't filled with a color")
      return
    }
    #expect(color == CGColor.opaqueBlack)
  }

  @Test("a pattern takes the attributes and the content of the pattern that it references")
  func patternReference() async throws {
    let tree = try await renderTree(
      ##"""
      <pattern id="a" width="1" height="1"><rect width="5" height="5"/></pattern>
      <pattern id="b" href="#a" patternUnits="userSpaceOnUse" x="2" width="10" height="10"/>
      <rect width="20" height="20" fill="url(#b)"/>
      """##)
    let rect = try shape(try children(of: tree).last)
    guard case .vector(.pattern(let paint), _, _) = rect.content else {
      Issue.record("The rectangle isn't filled with a pattern")
      return
    }
    let pattern = try #require(paint)
    #expect(pattern.tileSize == CGSize(width: 10, height: 10))
    #expect(pattern.origin == CGPoint(x: 2, y: 0))
    let content = try shape(pattern.content.first)
    #expect(content.id.instance == [rect.id.element])
  }

  @Test("a pattern that its content references again paints black there")
  func patternCycle() async throws {
    let tree = try await renderTree(
      ##"""
      <pattern id="p" width="1" height="1"><rect width="1" height="1" fill="url(#p)"/></pattern>
      <rect width="20" height="20" fill="url(#p)"/>
      """##)
    guard case .vector(.pattern(let paint), _, _) = try shape(try children(of: tree).last).content else {
      Issue.record("The rectangle isn't filled with a pattern")
      return
    }
    let content = try shape(try #require(paint).content.first)
    guard case .vector(.color(let color), _, _) = content.content else {
      Issue.record("The content of the pattern isn't filled with a color")
      return
    }
    #expect(color == CGColor.opaqueBlack)
  }

  /// Attributes of a flood, and its color, premultiplied, in the order of the pixels of the bitmap.
  private static let floodColors: [(String, [Int])] = [
    (#"flood-color="lime""#, [0, 255, 0, 255]),
    (#"flood-color="rgba(0, 255, 0, 0.5)""#, [0, 128, 0, 128]),
    (#"flood-color="lime" flood-opacity="0.5""#, [0, 128, 0, 128]),
    (#"flood-color="rgba(0, 255, 0, 0.5)" flood-opacity="0.5""#, [0, 64, 0, 64]),
    (#"flood-color="hsla(120, 100%, 25%, 0.5)""#, [0, 64, 0, 128]),
    (##"flood-color="#0f0""##, [0, 255, 0, 255]),
    (##"flood-color="#0f08""##, [0, 136, 0, 136]),
    (##"flood-color="#00ff0080""##, [0, 128, 0, 128]),
  ]

  @Test("a flood premultiplies its color by the alpha of the color and the flood opacity", arguments: floodColors)
  func floodColor(attributes: String, expected: [Int]) async throws {
    let filtered = try await filteredNode(
      ##"<filter id="f"><feFlood "## + attributes + ##"/></filter><rect width="10" height="10" filter="url(#f)"/>"##)
    guard case .flood(let color) = try #require(filtered.primitives.first).primitive else {
      Issue.record("The primitive isn't a flood")
      return
    }
    #expect(color.count == 4)
    for (component, value) in zip(color, expected) {
      #expect(abs(Int(component) - value) <= 1, "\(color) isn't \(expected)")
    }
  }

  @Test("an element with a filter keeps itself without the filter, which is the source image")
  func filterSource() async throws {
    let filtered = try await filteredNode(
      ##"<filter id="f"><feOffset dx="1"/></filter><rect width="10" height="10" filter="url(#f)"/>"##)
    let source = try shape(filtered.source)
    #expect(source.geometry?.frame == CGRect(x: 0, y: 0, width: 10, height: 10))
  }

  @Test("a filter resolves its region and the values of its primitives for the bounds of the element")
  func filterValues() async throws {
    let filtered = try await filteredNode(
      ##"""
      <filter id="f" primitiveUnits="objectBoundingBox">
        <feOffset dx="0.5" result="a"/>
        <feGaussianBlur stdDeviation="0.1 0.2" in="a" x="0" width="0.5"/>
        <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
      </filter>
      <rect x="10" width="10" height="5" filter="url(#f)"/>
      """##)
    #expect(filtered.frame == CGRect(x: 10, y: 0, width: 10, height: 5))
    #expect(filtered.effectRect == CGRect(x: 9, y: -0.5, width: 12, height: 6))
    #expect(filtered.primitives.map(\.isFirst) == [true, false, false])
    #expect(filtered.primitives.first?.result == "a")
    guard case .offset(let translation) = filtered.primitives[0].primitive else {
      Issue.record("The first primitive isn't an offset")
      return
    }
    #expect(translation == CGAffineTransform(translationX: 5, y: 0))
    #expect(filtered.primitives[1].subregion == CGRect(x: 10, y: -0.5, width: 5, height: 6))
    guard case .gaussianBlur(let blur) = filtered.primitives[1].primitive,
      case .hetero(let x, let y) = blur.standardDeviation
    else {
      Issue.record("The second primitive isn't a Gaussian blur with two standard deviations")
      return
    }
    #expect(x == 1)
    #expect(y == 1)
    guard case .merge(let inputs, _) = filtered.primitives[2].primitive else {
      Issue.record("The third primitive isn't a merge")
      return
    }
    #expect(inputs.count == 2)
    #expect(inputs.first.map { $0 == nil } == true)
  }

  @Test("a filter without children draws nothing")
  func emptyFilter() async throws {
    let tree = try await renderTree(##"<filter id="f"/><rect width="10" height="10" filter="url(#f)"/>"##)
    #expect(try children(of: tree).count == 1)
  }

  @Test("a group or an svg element with display none draws nothing")
  func containersWithoutDisplay() async throws {
    let tree = try await renderTree(
      #"<g display="none"><rect width="10" height="10"/></g><svg display="none"><rect width="10" height="10"/></svg>"#)
    #expect(try children(of: tree).isEmpty)
  }

  @Test("the bounds of an svg element don't include its children with display none")
  func svgBoundsWithoutHiddenChildren() async throws {
    let tree = try await renderTree(
      ##"""
      <clipPath id="c"><rect width="10" height="10"/></clipPath>
      <g clip-path="url(#c)">
        <svg width="20" height="20"><rect x="10" width="10" height="10" display="none"/><rect width="5" height="5"/></svg>
      </g>
      """##)
    guard case .group(let group) = try children(of: tree).last else {
      Issue.record("The last child isn't a group")
      return
    }
    #expect(try #require(group.clip).frame == CGRect(x: 0, y: 0, width: 5, height: 5))
  }

  @Test("a group, an svg element and a use element are masked for their bounds")
  func containerMasks() async throws {
    let tree = try await renderTree(
      ##"""
      <mask id="m"><rect width="20" height="20" fill="white"/></mask>
      <g mask="url(#m)"><rect x="2" width="5" height="5"/></g>
      <svg width="10" height="10" viewBox="0 0 5 5" mask="url(#m)"><rect width="5" height="5"/></svg>
      <use href="#r" x="3" mask="url(#m)"/>
      <defs><rect id="r" width="4" height="4"/></defs>
      """##)
    let nodes = try children(of: tree)
    guard case .group(let group) = nodes[0], case .viewport(let svg) = nodes[1], case .use(let use) = nodes[2] else {
      Issue.record("The children aren't a group, an svg element and a use element")
      return
    }
    let groupMask = try #require(group.mask)
    #expect(groupMask.frame == CGRect(x: 2, y: 0, width: 5, height: 5))
    #expect(groupMask.region == CGRect(x: -2, y: -2, width: 24, height: 24))
    let svgContent = try #require(svg.content)
    #expect(try #require(svgContent.mask).frame == CGRect(x: 0, y: 0, width: 5, height: 5))
    #expect(try #require(use.mask).frame == CGRect(x: 3, y: 0, width: 4, height: 4))
  }

  @Test("a gradient paints whether its display, or the display of its ancestor, is none")
  func gradientWithoutDisplay() async throws {
    let tree = try await renderTree(
      ##"""
      <linearGradient id="a" display="none"><stop stop-color="lime"/></linearGradient>
      <defs display="none"><linearGradient id="b"><stop stop-color="lime"/></linearGradient></defs>
      <rect width="10" height="10" fill="url(#a)"/>
      <rect width="10" height="10" fill="url(#b)"/>
      """##)
    for node in try children(of: tree).suffix(2) {
      guard case .vector(.gradient(.some), _, _) = try shape(node).content else {
        Issue.record("The rectangle isn't filled with a gradient")
        continue
      }
    }
  }

  @Test("a transform or a pattern transform that isn't valid is ignored")
  func invalidTransforms() async throws {
    let tree = try await renderTree(
      ##"""
      <pattern id="p" width="1" height="1" patternTransform="("><rect width="1" height="1"/></pattern>
      <rect width="10" height="10" transform="(" fill="url(#p)"/>
      """##)
    let rect = try shape(try children(of: tree).last)
    #expect(rect.transform == .identity)
    guard case .vector(.pattern(let paint), _, _) = rect.content else {
      Issue.record("The rectangle isn't filled with a pattern")
      return
    }
    #expect(try #require(paint).transform == .identity)
  }

  /// Elements with transforms, a point and where the transform of the last element moves the point.
  private static let transformedElements: [(String, CGPoint, CGPoint)] = [
    (
      #"<rect x="5" y="5" width="10" height="10" transform="rotate(90)" transform-origin="10 10"/>"#,
      CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 5)
    ),
    (
      #"<rect x="5" y="5" width="10" height="10" style="transform: scale(2); transform-box: fill-box; transform-origin: center"/>"#,
      CGPoint(x: 5, y: 5), CGPoint(x: 0, y: 0)
    ),
    (
      #"<rect x="5" y="5" width="10" height="10" stroke="black" stroke-width="2" style="transform: scale(2); transform-box: stroke-box"/>"#,
      CGPoint(x: 5, y: 5), CGPoint(x: 6, y: 6)
    ),
    (
      #"<rect x="5" y="5" width="10" height="10" stroke-width="2" style="transform: scale(2); transform-box: border-box"/>"#,
      CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)
    ),
    (
      #"<rect width="10" height="10" style="transform: translate(50%, 25%)"/>"#,
      CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5)
    ),
    (
      #"<rect x="2" width="4" height="8" style="transform: translate(50%, 25%); transform-box: fill-box"/>"#,
      CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 2)
    ),
    (
      #"<g style="transform: rotate(180deg); transform-box: fill-box; transform-origin: 50% 50%"><rect x="2" y="2" width="4" height="4"/></g>"#,
      CGPoint(x: 2, y: 2), CGPoint(x: 6, y: 6)
    ),
    (
      ##"<defs><rect id="r" width="4" height="4"/></defs><use href="#r" x="2" y="2" style="transform: scale(2); transform-box: content-box; transform-origin: right bottom"/>"##,
      CGPoint(x: 2, y: 2), CGPoint(x: -2, y: -2)
    ),
    // The transform of a nested svg element applies before its position, and its bounds are the bounds of its
    // content in the viewport.
    (
      #"<svg x="5" y="5" width="10" height="10" transform="rotate(90)" transform-origin="10 10"><rect width="10" height="10"/></svg>"#,
      CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 5)
    ),
    (
      #"<svg x="2" y="2" width="8" height="8" viewBox="0 0 4 4" style="transform: rotate(180deg); transform-box: fill-box; transform-origin: center"><rect x="1" y="1" width="2" height="2"/></svg>"#,
      CGPoint(x: 4, y: 4), CGPoint(x: 8, y: 8)
    ),
    (
      #"<g style="transform: rotate(180deg); transform-box: fill-box; transform-origin: center"><svg x="2" y="2" width="8" height="8" viewBox="0 0 4 4" transform="translate(2)"><rect x="1" y="1" width="2" height="2"/></svg></g>"#,
      CGPoint(x: 6, y: 4), CGPoint(x: 10, y: 8)
    ),
  ]

  @Test(
    "transforms apply about the transform origin, in the reference box of the transform box",
    arguments: transformedElements)
  func transformOrigins(content: String, point: CGPoint, expected: CGPoint) async throws {
    let node = try children(of: try await renderTree(content)).last
    let transform: CGAffineTransform =
      switch node {
      case .shape(let shape): shape.transform
      case .group(let group): group.transform
      case .use(let use): use.transform
      case .viewport(let viewport): viewport.transform
      default: throw NodeError.unexpected(node)
      }
    let moved = point.applying(transform)
    #expect(abs(moved.x - expected.x) < 1e-9 && abs(moved.y - expected.y) < 1e-9, "\(moved)")
  }

  @Test("the root svg element isn't transformed")
  func rootTransform() async throws {
    let tree = try await renderTree(#"<rect width="10" height="10"/>"#, attributes: #"transform="rotate(90)""#)
    guard case .viewport(let viewport) = tree.root else {
      Issue.record("The root isn't a viewport")
      return
    }
    #expect(viewport.transform == .identity)
  }

  @Test("the children of an svg element with a filter keep their transforms")
  func filteredViewportChildren() async throws {
    let tree = try await renderTree(
      ##"""
      <filter id="f"><feOffset dx="1"/></filter>
      <svg width="20" height="20" transform="translate(1 2)" filter="url(#f)">
        <rect width="5" height="5" transform="translate(3 4)"/>
      </svg>
      """##)
    guard case .filtered(let filtered) = try children(of: tree).last, case .viewport(let viewport) = filtered.source
    else {
      Issue.record("The svg element isn't filtered")
      return
    }
    #expect(filtered.transform == CGAffineTransform(translationX: 1, y: 2))
    #expect(viewport.transform == .identity)
    let rect = try shape(try #require(viewport.content).children.first)
    #expect(rect.transform == CGAffineTransform(translationX: 3, y: 4))
  }

  @Test("the reference box of a clipPath element is the bounds of its content")
  func clipPathTransformBox() async throws {
    let tree = try await renderTree(
      ##"""
      <clipPath id="c" style="transform: scale(2); transform-box: fill-box; transform-origin: center">
        <rect x="2" y="2" width="4" height="4"/>
      </clipPath>
      <rect width="20" height="20" clip-path="url(#c)"/>
      """##)
    let clip = try #require(try shape(try children(of: tree).last).clip)
    #expect(CGPoint(x: 2, y: 2).applying(clip.transform) == .zero)
  }

  @Test("d in a style sheet overrides the attribute of a path")
  func pathDataInStyleSheet() async throws {
    let tree = try await renderTree(
      #"<style>#p { d: path("M0 0 H10 V10 Z") }</style><path id="p" d="M0 0 H5 V5 Z"/>"#)
    let path = try shape(try children(of: tree).last)
    #expect(path.geometry?.frame == CGRect(x: 0, y: 0, width: 10, height: 10))
  }

  @Test("the content of a use element is animated at the time of the document")
  func animatedUseContent() async throws {
    let tree = try await renderTree(
      ##"""
      <style>@keyframes a { from { opacity: 0 } to { opacity: 1 } }</style>
      <defs><rect id="r" width="10" height="10" style="animation: a 1s linear"/></defs>
      <use href="#r"/>
      """##, at: 0.25)
    let node = try #require(children(of: tree).last)
    let instance = try #require(try use(node).instance)
    let content = try shape(instance.content)
    #expect(content.opacity == 0.25)
  }

  private func filteredNode(_ content: String) async throws -> FilteredNode {
    let tree = try await renderTree(content)
    guard case .filtered(let filtered) = try children(of: tree).last else {
      throw NodeError.unexpected(try children(of: tree).last)
    }
    return filtered
  }
}
