import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The IDs of the elements of a document whose render nodes can change.
private func unstable(in base: SVGBaseContext) -> Set<String> {
  let elements = base.restyleScope?.unstable ?? []
  return Set((base.root?.elements ?? []).filter { elements.contains($0.base.elementID) }.compactMap(\.base.id))
}

/// The render tree of a document at a time, rendered into 100 by 100.
private func tree(
  of base: SVGBaseContext, reusing previous: RenderNodeCache = .init(), changed: Set<ElementID>? = nil
) async throws -> RenderTree {
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet))
  return try #require(
    await RenderTreeBuilder(
      base: base, viewPort: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1, reusing: previous, changed: changed
    )
    .build(fit: fit))
}

/// The colors that the shapes of a node fill, in order.
private func fills(of node: RenderNode?) -> [String] {
  switch node {
  case .shape(let shape):
    switch shape.content {
    case .vector(.color(let color)?, _, _)?: return ["\(color.components ?? [])"]
    // The content of a pattern counts as the fills of the shape that it fills.
    case .vector(.pattern(let pattern?)?, _, _)?: return pattern.content.flatMap(fills)
    default: return []
    }
  case .group(let group): return group.children.flatMap(fills)
  case .viewport(let viewport): return (viewport.content?.children ?? []).flatMap(fills)
  case .use(let use): return fills(of: use.instance?.content)
  case .filtered(let filtered): return fills(of: filtered.source)
  case nil: return []
  }
}

@Suite("Reusing render nodes")
struct RenderNodeReuseTests {
  private static let keyframes = "<style>@keyframes k { to { fill: lime } }</style>"

  /// Documents, and the IDs of the elements whose render nodes can change.
  private static let documents: [(String, Set<String>)] = [
    // An element that doesn't change makes the same node, and the ancestors of one that changes don't.
    (
      keyframes + #"<g id="g"><rect id="a" width="10" height="10" style="animation: k 1s"/>"#
        + #"<rect id="b" width="10" height="10"/></g><rect id="c" width="10" height="10"/>"#,
      ["g", "a"]
    ),
    // An element that references one that changes, through any reference, changes with it.
    (
      keyframes + #"<defs><rect id="d" width="10" height="10" style="animation: k 1s"/></defs>"#
        + ##"<use id="u" href="#d"/><use id="v" href="#u"/><rect id="c" width="10" height="10"/>"##,
      ["d", "u", "v"]
    ),
    (
      #"<linearGradient id="l"><stop offset="0" stop-color="red"><animate attributeName="stop-color" to="lime" dur="1s"/>"#
        + ##"</stop></linearGradient><linearGradient id="m" href="#l"/>"##
        + ##"<rect id="a" width="10" height="10" fill="url(#m)"/><rect id="c" width="10" height="10"/>"##,
      ["l", "m", "a"]
    ),
    (
      #"<clipPath id="p"><rect id="r" width="5" height="5"><animate attributeName="width" to="10" dur="1s"/></rect>"#
        + ##"</clipPath><g id="g"><rect id="a" width="10" height="10" clip-path="url(#p)"/></g>"##,
      ["p", "r", "g", "a"]
    ),
  ]

  @Test("the elements whose render nodes can change", arguments: documents)
  func unstableElements(content: String, expected: Set<String>) {
    #expect(unstable(in: parse(content)) == expected)
  }

  @Test("a render tree reuses the nodes of the elements that don't change, and makes the others again")
  func reuses() async throws {
    let base = parse(
      ##"<defs><rect id="d" width="10" height="10"/></defs><g fill="red"><use href="#d"/></g>"##
        + ##"<use id="u" href="#d" fill="red"><set attributeName="fill" to="lime" begin="0.5s"/></use>"##)
    let first = try await tree(of: base.at(time: 0))
    let second = try await tree(of: base.at(time: 1), reusing: first.reusableNodes)
    let fresh = try await tree(of: base.at(time: 1))
    // The `<use>` whose fill changes shows its content in the new color, although the content doesn't change.
    #expect(fills(of: second.root) == fills(of: fresh.root))
    #expect(fills(of: second.root) != fills(of: first.root))
    #expect(!second.reusableNodes.nodes.isEmpty)
  }

  @Test(
    "the line that an element around text declares changes with the paint of the element",
    arguments: [
      #"<g fill="red" text-decoration="underline"><set attributeName="fill" to="lime" begin="0.5s"/>"#,
      #"<g fill="red" text-decoration="underline" style="animation: k 1s linear">"#,
    ])
  func decorationAroundText(group: String) async throws {
    let base = parse(
      Self.keyframes + group + #"<text x="10" y="50" font-size="20" fill="blue">a</text></g>"#
        + #"<rect width="10" height="10"/>"#)
    let first = try await tree(of: base.at(time: 0))
    let second = try await tree(of: base.at(time: 0.7), reusing: first.reusableNodes)
    let fresh = try await tree(of: base.at(time: 0.7))
    #expect(fills(of: second.root) == fills(of: fresh.root))
    #expect(fills(of: second.root) != fills(of: first.root))
  }

  @Test("the line that an element around text declares changes with a change of the paint of the element")
  func changedDecorationAroundText() async throws {
    let base = parse(
      #"<g id="g" fill="red" text-decoration="underline"><text x="10" y="50" font-size="20" fill="blue">a</text></g>"#
        + #"<rect width="10" height="10"/>"#)
    let first = try await tree(of: base, changed: [])
    let g = try #require(base.document.element(id: "g"))
    let changed = base.changingAttributes([g: ["fill": "lime"]])
    var changes = DocumentChanges()
    changes.attributes = [g]
    changes.paintingAttributes = [g]
    let nodes = try #require(changed.changedNodes(since: base, by: changed.changedElements(by: changes)))
    let second = try await tree(of: changed, reusing: first.reusableNodes, changed: nodes.nodes)
    let fresh = try await tree(of: changed)
    #expect(!first.reusableNodes.nodes.isEmpty)
    #expect(fills(of: second.root) == fills(of: fresh.root))
    #expect(fills(of: second.root) != fills(of: first.root))
  }

  @Test("the line that an element around a pattern declares changes with a change of the paint of the element")
  func changedDecorationAroundPattern() async throws {
    let base = parse(
      #"<g id="g" fill="red" text-decoration="underline"><pattern id="p" width="100" height="100" "#
        + #"patternUnits="userSpaceOnUse"><text x="10" y="50" font-size="20" fill="blue">a</text></pattern></g>"#
        + #"<rect width="100" height="100" fill="url(#p)"/>"#)
    let first = try await tree(of: base, changed: [])
    let g = try #require(base.document.element(id: "g"))
    let changed = base.changingAttributes([g: ["fill": "lime"]])
    var changes = DocumentChanges()
    changes.attributes = [g]
    changes.paintingAttributes = [g]
    let nodes = try #require(changed.changedNodes(since: base, by: changed.changedElements(by: changes)))
    let second = try await tree(of: changed, reusing: first.reusableNodes, changed: nodes.nodes)
    let fresh = try await tree(of: changed)
    #expect(fills(of: second.root) == fills(of: fresh.root))
    #expect(fills(of: second.root) != fills(of: first.root))
  }
}
