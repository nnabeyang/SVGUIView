import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The IDs of the elements of a document in a set of element identifiers.
private func ids(_ elements: Set<ElementID>, in base: SVGBaseContext) -> Set<String> {
  Set((base.root?.elements ?? []).filter { elements.contains($0.base.elementID) }.compactMap(\.base.id))
}

/// The pixels of a document rendered into a bitmap of 100 by 100.
private func pixels(of base: SVGBaseContext) async throws -> [UInt8] {
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(await RenderTreeBuilder(base: base, viewPort: rect, scale: 1).build(fit: fit))
  var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
  let context = try #require(
    CGContext(
      data: &pixels, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.concatenate(CGAffineTransform(1, 0, 0, -1, 0, 100))
  await CGPainterProxy.paint(tree, into: context)
  return pixels
}

/// Paints render trees without depending on SVGRenderCG, which the tests of SVGCore don't import: the shapes are
/// filled with their colors, which shows the computed values that the trees come from.
private enum CGPainterProxy {
  static func paint(_ tree: RenderTree, into context: CGContext) async {
    for transform in tree.rootTransforms {
      context.concatenate(transform)
    }
    if let root = tree.root {
      paint(root, into: context)
    }
  }

  private static func paint(_ node: RenderNode, into context: CGContext) {
    context.saveGState()
    defer { context.restoreGState() }
    context.concatenate(node.transform)
    switch node {
    case .shape(let shape):
      guard let geometry = shape.geometry, case .vector(let fill, _, _)? = shape.content else { return }
      context.setAlpha(shape.opacity)
      if case .color(let color)? = fill {
        context.setFillColor(color)
        context.addPath(geometry.path.cgPath)
        context.fillPath()
      }
    case .group(let group):
      context.setAlpha(group.opacity)
      group.children.forEach { paint($0, into: context) }
    case .viewport(let viewport):
      context.concatenate(viewport.translation)
      if let content = viewport.content {
        context.concatenate(content.viewBoxTransform)
        content.children.forEach { paint($0, into: context) }
      }
    case .use(let use):
      if let instance = use.instance {
        context.concatenate(instance.translation)
        context.setAlpha(instance.opacity)
        instance.content.map { paint($0, into: context) }
      }
    case .filtered(let filtered):
      filtered.source.map { paint($0, into: context) }
    }
  }
}

@Suite("Computing the style again for animations")
struct IncrementalStyleTests {
  /// Documents, the IDs of the elements whose computed values can change, and the IDs of the elements that have them
  /// in their subtrees.
  private static let scopes: [(String, Set<String>, Set<String>)] = [
    (#"<rect id="a" width="10" height="10"/>"#, [], []),
    // A CSS animation changes the element that runs it and its descendants, whatever the properties.
    (
      #"<style>@keyframes k { to { fill: lime } }</style><g id="g"><g id="h" style="animation: k 1s">"#
        + #"<rect id="a" width="10" height="10"/></g><rect id="b" width="10" height="10"/></g>"#,
      ["h", "a"], ["g", "h", "a"]
    ),
    (
      #"<style>@keyframes k { to { fill: lime } }</style><rect id="a" width="10" height="10" style="animation: z 1s"/>"#,
      [], []
    ),
    // A SMIL animation changes its target and the target's descendants.
    (
      #"<g id="g"><rect id="a" width="10" height="10"><animate attributeName="x" to="5" dur="1s"/></rect></g>"#
        + #"<rect id="b" width="10" height="10"/>"#,
      ["a"], ["g", "a"]
    ),
    (
      ##"<rect id="a" width="10" height="10"/><g id="g"><animate href="#a" attributeName="x" to="5" dur="1s"/></g>"##,
      ["a"], ["a"]
    ),
  ]

  @Test("the elements whose computed values animations can change", arguments: scopes)
  func scope(content: String, changing: Set<String>, containing: Set<String>) throws {
    let base = parse(content)
    let scope = base.restyleScope
    #expect(ids(scope?.changing ?? [], in: base) == changing)
    #expect(ids(scope?.containing ?? [], in: base) == containing)
  }

  @Test("the subtrees without an element that animations change stay the same")
  func reusesSubtrees() throws {
    let base = parse(
      #"<style>@keyframes k { to { fill: lime } }</style><g id="s"><rect width="10" height="10"/></g>"#
        + #"<g id="g"><rect id="r" width="10" height="10" style="animation: k 1s"/><rect id="t" width="5" height="5"/></g>"#
    )
    let next = base.at(time: 0.5)
    func element(_ id: String, in context: SVGBaseContext) throws -> any SVGElement {
      try #require(context.root?.elements.first { $0.base.id == id })
    }
    let (static0, static1) = (try element("s", in: base), try element("s", in: next))
    let (sibling0, sibling1) = (try element("t", in: base), try element("t", in: next))
    let (group0, group1) = (try element("g", in: base), try element("g", in: next))
    let (animated0, animated1) = (try element("r", in: base), try element("r", in: next))
    #expect(static1 === static0)
    #expect(sibling1 === sibling0)
    // The group around the animated rectangle is made again, with the computed values that it had.
    #expect(group1 !== group0)
    #expect(group1.base === group0.base)
    #expect(animated1.base !== animated0.base)
  }

  /// Documents with animations of properties that the descendants inherit, of the root, and of elements that other
  /// elements use.
  private static let documents = [
    #"<style>@keyframes k { from { fill: red } to { fill: lime } }</style>"#
      + #"<g style="animation: k 1s linear"><rect width="40" height="40"/><g><rect x="50" width="40" height="40"/></g></g>"#
      + #"<rect y="50" width="40" height="40" fill="blue"/>"#,
    #"<style>@keyframes k { from { font-size: 10px } to { font-size: 30px } } svg { animation: k 1s linear }</style>"#
      + #"<rect width="2em" height="2em" fill="green"/><rect x="50" width="3rem" height="1rem" fill="blue"/>"#,
    ##"<defs><rect id="d" width="20" height="20"><animate attributeName="fill" from="red" to="lime" dur="1s"/></rect></defs>"##
      + ##"<use href="#d" x="10" y="10"/><use href="#d" x="60" y="60" fill="blue"/>"##,
    #"<g opacity="0.5"><rect width="50" height="50" fill="red"><animate attributeName="opacity" to="0" dur="1s"/>"#
      + #"<animateTransform attributeName="transform" type="translate" to="20 20" dur="1s"/></rect>"#
      + #"<rect x="50" y="50" width="50" height="50" fill="blue"/></g>"#,
  ]

  @Test("a document at a time looks the same as with every computed value computed again", arguments: documents)
  func sameAsFully(content: String) async throws {
    let base = parse(content)
    for time in [0, 0.25, 0.5, 2] {
      #expect(try await pixels(of: base.at(time: time)) == pixels(of: base.restyledFully(at: time)), "at \(time)")
    }
  }
}
