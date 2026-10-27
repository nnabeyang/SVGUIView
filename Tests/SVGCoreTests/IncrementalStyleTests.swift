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
}
