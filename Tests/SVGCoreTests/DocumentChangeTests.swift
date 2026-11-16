import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// The IDs of the elements of a document in a set of element identifiers.
private func ids(_ elements: Set<ElementID>?, in base: SVGBaseContext) -> Set<String> {
  Set((base.root?.elements ?? []).filter { elements?.contains($0.base.elementID) ?? false }.compactMap(\.base.id))
}

@Suite("Changing the attributes of a document")
struct DocumentChangeTests {
  /// A change to an attribute: the ID of the element, the name of the attribute, and the value, or `nil` to remove
  /// it.
  typealias Change = (element: String, attribute: String, value: String?)

  private static let keyframes = "<style>@keyframes k { to { fill: lime } } .on { animation: k 1s }</style>"

  /// Documents, a change, and the document as it's written with the change.
  private static let changes: [(String, Change, String)] = [
    (
      #"<rect id="a" width="50" height="50" fill="red"/>"#, ("a", "fill", "lime"),
      #"<rect id="a" width="50" height="50" fill="lime"/>"#
    ),
    (
      #"<rect id="a" width="50" height="50" fill="red"/>"#, ("a", "fill", nil),
      #"<rect id="a" width="50" height="50"/>"#
    ),
    (
      #"<style>.on { fill: lime }</style><rect id="a" width="50" height="50" fill="red"/>"#, ("a", "class", "on"),
      #"<style>.on { fill: lime }</style><rect id="a" width="50" height="50" fill="red" class="on"/>"#
    ),
    (
      #"<rect id="a" width="50" height="50" fill="red"/>"#, ("a", "style", "fill: lime; opacity: 0.5"),
      #"<rect id="a" width="50" height="50" fill="red" style="fill: lime; opacity: 0.5"/>"#
    ),
    // A reference finds the element with a new ID, and no longer finds the element whose ID changes.
    (
      ##"<defs><rect id="x" width="50" height="50" fill="lime"/><rect id="t" width="50" height="50" fill="red"/>"##
        + ##"</defs><use href="#t"/>"##, ("x", "id", "t"),
      ##"<defs><rect id="t" width="50" height="50" fill="lime"/><rect id="t" width="50" height="50" fill="red"/>"##
        + ##"</defs><use href="#t"/>"##
    ),
    (
      ##"<defs><rect id="r" width="50" height="50" fill="red"/><rect id="l" width="50" height="50" fill="lime"/>"##
        + ##"</defs><use id="u" href="#r"/>"##, ("u", "href", "#l"),
      ##"<defs><rect id="r" width="50" height="50" fill="red"/><rect id="l" width="50" height="50" fill="lime"/>"##
        + ##"</defs><use id="u" href="#l"/>"##
    ),
    (
      ##"<linearGradient id="g"/><rect id="a" width="50" height="50" fill="url(#h)"/>"##, ("g", "id", "h"),
      ##"<linearGradient id="h"/><rect id="a" width="50" height="50" fill="url(#h)"/>"##
    ),
    // A change changes the computed values of the descendants, and of the later siblings through sibling
    // combinators.
    (
      #"<g id="g" fill="red"><rect width="50" height="50"/></g>"#, ("g", "fill", "lime"),
      #"<g id="g" fill="lime"><rect width="50" height="50"/></g>"#
    ),
    (
      #"<style>.a rect { fill: lime }</style><g id="g"><g><rect width="50" height="50" fill="red"/></g></g>"#,
      ("g", "class", "a"),
      #"<style>.a rect { fill: lime }</style><g id="g" class="a"><g><rect width="50" height="50" fill="red"/></g></g>"#
    ),
    (
      #"<style>.a + rect { fill: lime }</style><rect id="a" width="10" height="10"/><rect width="50" height="50"/>"#,
      ("a", "class", "a"),
      #"<style>.a + rect { fill: lime }</style><rect id="a" width="10" height="10" class="a"/>"#
        + #"<rect width="50" height="50"/>"#
    ),
    (
      #"<style>:is(.a ~ g) rect { fill: lime }</style><rect id="a" width="10" height="10"/><circle r="1"/>"#
        + #"<g><rect width="50" height="50"/></g>"#, ("a", "class", "a"),
      #"<style>:is(.a ~ g) rect { fill: lime }</style><rect id="a" width="10" height="10" class="a"/><circle r="1"/>"#
        + #"<g><rect width="50" height="50"/></g>"#
    ),
    (
      #"<style>.a ~ rect { fill: lime }</style><rect width="50" height="50"/><rect id="b" width="10" height="10"/>"#,
      ("b", "class", "a"),
      #"<style>.a ~ rect { fill: lime }</style><rect width="50" height="50"/>"#
        + #"<rect id="b" width="10" height="10" class="a"/>"#
    ),
    // The elements that references find are the changed ones.
    (
      ##"<linearGradient id="g"><stop id="s" stop-color="red"/></linearGradient>"##
        + ##"<rect width="50" height="50" fill="url(#g)"/>"##, ("s", "stop-color", "lime"),
      ##"<linearGradient id="g"><stop id="s" stop-color="lime"/></linearGradient>"##
        + ##"<rect width="50" height="50" fill="url(#g)"/>"##
    ),
    (
      ##"<clipPath id="c"><rect id="r" width="10" height="10"/></clipPath>"##
        + ##"<rect width="50" height="50" fill="lime" clip-path="url(#c)"/>"##, ("r", "width", "50"),
      ##"<clipPath id="c"><rect id="r" width="50" height="10"/></clipPath>"##
        + ##"<rect width="50" height="50" fill="lime" clip-path="url(#c)"/>"##
    ),
    // SMIL animations and CSS animations change with the attributes that they come from.
    (
      #"<rect id="a" width="10" height="50" fill="lime"><animate id="m" to="100" dur="1s"/></rect>"#,
      ("m", "attributeName", "width"),
      #"<rect id="a" width="10" height="50" fill="lime"><animate id="m" attributeName="width" to="100" dur="1s"/>"#
        + "</rect>"
    ),
    (
      #"<rect id="a" width="10" height="50" fill="lime"><animate id="m" attributeName="width" to="100" dur="1s"/>"#
        + "</rect>", ("m", "dur", "2s"),
      #"<rect id="a" width="10" height="50" fill="lime"><animate id="m" attributeName="width" to="100" dur="2s"/>"#
        + "</rect>"
    ),
    (
      keyframes + #"<rect id="a" width="50" height="50" fill="red"/>"#, ("a", "class", "on"),
      keyframes + #"<rect id="a" width="50" height="50" fill="red" class="on"/>"#
    ),
    (
      keyframes + #"<rect id="a" width="50" height="50" fill="red" class="on"/>"#, ("a", "class", nil),
      keyframes + #"<rect id="a" width="50" height="50" fill="red"/>"#
    ),
  ]

  @Test("the context of a changed document is the context of the document written with the change", arguments: changes)
  func changedContext(content: String, change: Change, expected: String) async throws {
    let base = parse(content)
    let id = try #require(base.document.element(id: change.element))
    let changed = base.changingAttributes([id: [change.attribute: change.value]])
    let written = parse(expected)
    #expect(changed.document.attributes(of: id) == written.document.attributes(of: id))
    #expect(changed.isAnimated == written.isAnimated)
    #expect(changed.animations.smil.count == written.animations.smil.count)
    for scope in [\RestyleScope.changing, \.containing, \.unstable] {
      #expect(
        ids(changed.restyleScope?[keyPath: scope], in: changed)
          == ids(written.restyleScope?[keyPath: scope], in: written))
    }
    #expect(Set(changed.contentIdMap.keys) == Set(written.contentIdMap.keys))
    #expect(Set(changed.pservers.keys) == Set(written.pservers.keys))
    // The tables find the elements of the changed tree.
    #expect(Set(changed.contents.keys) == Set((changed.root?.elements ?? []).map(\.index)))
    #expect(changed.contents.allSatisfy { $0.key == $0.value.index })
    func attributes(_ element: any SVGElement) -> [String: String] { element.base.attributes }
    for name in changed.contentIdMap.keys {
      #expect(changed[name].map(attributes) == written[name].map(attributes), "\(name)")
    }
    #expect(changed.pservers.mapValues(attributes) == written.pservers.mapValues(attributes))
    #expect(changed.clipPaths.mapValues(attributes) == written.clipPaths.mapValues(attributes))
    #expect(changed.markers.mapValues(attributes) == written.markers.mapValues(attributes))
    for time in [0, 0.5] {
      #expect(try await pixels(of: changed.at(time: time)) == pixels(of: written.at(time: time)), "at \(time)")
    }
  }

  @Test("a change keeps the playback of the animations of the elements that it doesn't change")
  func keepsPlayback() throws {
    let base = parse(
      Self.keyframes + #"<g id="g"><rect id="a" width="50" height="50"/></g><rect id="b" width="50" height="50"/>"#)
    let a = try #require(base.document.element(id: "a"))
    let b = try #require(base.document.element(id: "b"))
    // The animation of a descendant of a group starts at the time of the change.
    let started = base.changingAttributes([a: ["class": "on"]], at: 0.5)
    #expect(started.animations.playback.keys.map(\.element) == [a])
    let changed = started.changingAttributes([b: ["fill": "lime"]], at: 0.7)
    #expect(changed.animations.playback == started.animations.playback)
  }

  @Test("removing an element leaves out the playback of its animations")
  func removedPlayback() throws {
    let base = parse(
      Self.keyframes + #"<g id="g"><rect id="a" width="50" height="50"/><rect id="b" width="50" height="50"/></g>"#)
    let g = try #require(base.document.element(id: "g"))
    let a = try #require(base.document.element(id: "a"))
    let started = base.changingAttributes([a: ["class": "on"]], at: 0.5)
    #expect(!started.animations.playback.isEmpty)
    let tree = try #require(started.document.removing(a)).tree
    var changes = DocumentChanges()
    changes.restructured = [g]
    #expect(started.changing(to: tree, changes: changes, at: 0.7).animations.playback.isEmpty)
  }

  @Test("a change copies the changed element and its ancestors, and shares every other element")
  func sharesElements() throws {
    let base = parse(#"<g id="g"><rect id="a"/><rect id="b"/></g><g id="h"><rect id="c"/></g>"#)
    let a = try #require(base.document.element(id: "a"))
    let changed = base.document.changingAttributes([a: ["fill": "lime", "id": nil]])
    let before = try #require(base.document.root)
    let after = try #require(changed.root)
    #expect(after !== before)
    #expect(after.children[0] !== before.children[0])
    #expect(after.children[0].children[1] === before.children[0].children[1])
    #expect(after.children[1] === before.children[1])
    // The changed element keeps its identifier and position.
    #expect(changed.attributes(of: a) == ["fill": "lime"])
    #expect(changed.cursor(at: a)?.element === after.children[0].children[0])
    #expect(changed.element(id: "a") == nil)
  }

  @Test("a change makes again only the elements whose computed values it can change")
  func sharesRenderedElements() throws {
    let base = parse(
      #"<g id="g"><rect id="a"/><rect id="b"/></g><g id="h"><rect id="c"/></g>"#
        + #"<style>.x ~ rect { fill: lime }</style><g><rect id="d"/><rect id="e"/><rect id="f"/></g>"#)
    func element(_ id: String, in base: SVGBaseContext) -> (any SVGElement)? {
      base.root?.elements.first { $0.base.id == id }
    }
    let a = try #require(base.document.element(id: "a"))
    let e = try #require(base.document.element(id: "e"))
    let changed = base.changingAttributes([a: ["fill": "lime"], e: ["class": "x"]])
    for (id, isShared) in [
      ("g", false), ("a", false), ("b", false), ("h", true), ("c", true), ("d", true), ("e", false), ("f", false),
    ] {
      let before = try #require(element(id, in: base))
      let after = try #require(element(id, in: changed))
      #expect((before === after) == isShared, "\(id)")
    }
  }

  @Test("changes to several elements and to elements that the document doesn't have")
  func severalChanges() throws {
    let base = parse(#"<rect id="a"/><rect id="b"/>"#)
    let a = try #require(base.document.element(id: "a"))
    let b = try #require(base.document.element(id: "b"))
    let changed = base.document.changingAttributes([
      a: ["x": "1"], b: ["x": "2"], ElementID(rawValue: 1000): ["x": "3"],
    ])
    #expect(changed.attributes(of: a) == ["id": "a", "x": "1"])
    #expect(changed.attributes(of: b) == ["id": "b", "x": "2"])
    #expect(base.changingAttributes([:]).root === base.root)
  }
}
