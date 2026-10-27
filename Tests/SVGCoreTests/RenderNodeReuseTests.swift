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
}
