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

  @Test("a document at a time finds the same elements by their IDs as with every element made again")
  func sameReferences() throws {
    let base = parse(
      #"<style>@keyframes k { to { fill: lime } }</style>"#
        + #"<defs><linearGradient id="l"><stop offset="0" stop-color="red"/></linearGradient>"#
        + #"<clipPath id="c"><rect id="cr" width="5" height="5" style="animation: k 1s"/></clipPath>"#
        + #"<mask id="m"><rect width="5" height="5" fill="white"/></mask>"#
        + #"<pattern id="p" width="4" height="4"><rect id="pr" width="2" height="2" style="animation: k 1s"/></pattern>"#
        + #"<filter id="f"><feFlood flood-color="red"/></filter></defs>"#
        + #"<g id="g" style="animation: k 1s"><rect id="a" width="10" height="10"/></g><rect id="b" width="10" height="10"/>"#
    )
    let next = base.at(time: 0.5)
    let full = base.restyledFully(at: 0.5)
    for id in ["g", "a", "b"] {
      let found = try #require(next[id])
      #expect(found.base.elementID == full[id]?.base.elementID, "\(id)")
      // The element that the context finds is the one in its tree.
      #expect(next.root?.elements.contains { $0 === found } == true, "\(id)")
    }
    #expect(next.pservers["l"]?.base.elementID == full.pservers["l"]?.base.elementID)
    for (map, fullMap) in [
      (next.clipPaths.mapValues(\.index), full.clipPaths.mapValues(\.index)),
      (next.masks.mapValues(\.index), full.masks.mapValues(\.index)),
      (next.patterns.mapValues(\.index), full.patterns.mapValues(\.index)),
      (next.filters.mapValues(\.index), full.filters.mapValues(\.index)),
    ] {
      #expect(Set(map.keys) == Set(fullMap.keys))
      // The elements that the maps hold are the ones in the tree of the context.
      for value in map.values {
        #expect(next.root?.elements.contains { $0.index == value } == true)
      }
    }
    #expect(next.contents.count == full.contents.count)
  }
}
