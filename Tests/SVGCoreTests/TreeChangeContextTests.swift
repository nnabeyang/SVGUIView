import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// An edit of the tree of a document, which records the changes that the document API records for it. Elements are
/// found by their `k` attribute, since the edits change which elements IDs name.
enum TreeEdit: Sendable {
  /// Inserts a new element with attributes among the children of an element.
  case insert(String, [String: String], into: String, at: Int)
  /// Moves an element among the children of an element, at a position among the children without it.
  case move(String, into: String, at: Int)
  case remove(String)
  /// Replaces the children of an element with character data.
  case setText(String, String)
}

extension DocumentTree {
  /// The element whose `k` attribute is the key.
  fileprivate func element(key: String) throws -> ElementID {
    func find(_ element: DocumentElement) -> ElementID? {
      if element.attributes["k"] == key { return element.id }
      return element.children.lazy.compactMap(find).first
    }
    return try #require(root.flatMap(find), "The document has no element \(key)")
  }

  /// The document with an element taken out, which records the changes of the removal.
  fileprivate func taking(_ id: ElementID, changes: inout DocumentChanges) throws -> (DocumentTree, DocumentTree) {
    let parent = try #require(parent(of: id))
    let siblings = children(of: parent)
    if let following = siblings.firstIndex(of: id).flatMap({ siblings.dropFirst($0 + 1).first }) {
      changes.followingRemoved.insert(following)
    }
    changes.restructured.insert(parent)
    let (remaining, removed) = try #require(removing(id))
    return (remaining, removed)
  }

  /// The document with the edits made, and the changes that they record.
  func editing(_ edits: [TreeEdit]) throws -> (DocumentTree, DocumentChanges) {
    var tree = self
    var changes = DocumentChanges()
    for edit in edits {
      switch edit {
      case .insert(let name, let attributes, let parent, let index):
        let created = DocumentTree(
          elementNamed: name, identifier: try #require(tree.largestElementID) + 1, languages: tree.languages)
        let id = try #require(created.rootElement)
        let element = created.changingAttributes([id: attributes.mapValues { Optional($0) }])
        let parent = try tree.element(key: parent)
        tree = try #require(tree.inserting(element, into: parent, at: index))
        changes.restructured.insert(parent)
        changes.inserted.insert(id)
      case .move(let key, let parent, let index):
        let id = try tree.element(key: key)
        let (remaining, subtree) = try tree.taking(id, changes: &changes)
        let parent = try remaining.element(key: parent)
        tree = try #require(remaining.inserting(subtree, into: parent, at: index))
        changes.restructured.insert(parent)
        changes.inserted.insert(id)
      case .remove(let key):
        (tree, _) = try tree.taking(try tree.element(key: key), changes: &changes)
      case .setText(let key, let text):
        let id = try tree.element(key: key)
        let (replaced, removed) = try #require(tree.replacingChildren(of: id, withText: text))
        tree = replaced
        changes.texts.insert(id)
        if !removed.isEmpty { changes.restructured.insert(id) }
      }
    }
    return (tree, changes)
  }
}

/// Edits of the tree of a document, and the document as it's written with them.
struct TreeChangeCase: Sendable, CustomTestStringConvertible {
  let testDescription: String
  let before: String
  let edits: [TreeEdit]
  let after: String
}

@Suite("Changing the tree of the document of a context")
struct TreeChangeContextTests {
  static let cases: [TreeChangeCase] = [
    TreeChangeCase(
      testDescription: "inserting a shape without an ID",
      before: #"<g k="g"><rect id="a" width="10" height="10"/></g>"#,
      edits: [.insert("rect", ["x": "20", "width": "10", "height": "10"], into: "g", at: 1)],
      after: #"<g k="g"><rect id="a" width="10" height="10"/><rect x="20" width="10" height="10"/></g>"#),
    TreeChangeCase(
      testDescription: "inserting a shape before another one with its ID",
      before: ##"<g k="g"><rect id="a" width="10" height="10" fill="red"/></g><use href="#a" x="50"/>"##,
      edits: [.insert("rect", ["id": "a", "width": "20", "height": "20", "fill": "lime"], into: "g", at: 0)],
      after: #"<g k="g"><rect id="a" width="20" height="20" fill="lime"/><rect id="a" width="10" height="10" fill="red"/></g>"#
        + ##"<use href="#a" x="50"/>"##),
    TreeChangeCase(
      testDescription: "removing the first of two shapes with the same ID",
      before: #"<g k="g"><rect k="1" id="a" width="10" height="10" fill="red"/>"#
        + ##"<rect id="a" width="20" height="20" fill="lime"/></g><use href="#a" x="50"/>"##,
      edits: [.remove("1")],
      after: ##"<g k="g"><rect id="a" width="20" height="20" fill="lime"/></g><use href="#a" x="50"/>"##),
    TreeChangeCase(
      testDescription: "moving a shape before another one with its ID",
      before: #"<g k="g"><rect id="a" width="10" height="10" fill="red"/></g>"#
        + ##"<g k="h"><rect k="2" id="a" width="20" height="20" fill="lime"/></g><use href="#a" x="50"/>"##,
      edits: [.move("2", into: "g", at: 0)],
      after: #"<g k="g"><rect k="2" id="a" width="20" height="20" fill="lime"/>"#
        + ##"<rect id="a" width="10" height="10" fill="red"/></g><g k="h"/><use href="#a" x="50"/>"##),
    TreeChangeCase(
      testDescription: "inserting a clip path and its shape, which a shape is clipped with",
      before: #"<defs k="defs"/><rect width="50" height="50" fill="lime" clip-path="url(#c)"/>"#,
      edits: [
        .insert("clipPath", ["id": "c", "k": "c"], into: "defs", at: 0),
        .insert("circle", ["cx": "25", "cy": "25", "r": "20"], into: "c", at: 0),
      ],
      after: #"<defs k="defs"><clipPath id="c" k="c"><circle cx="25" cy="25" r="20"/></clipPath></defs>"#
        + #"<rect width="50" height="50" fill="lime" clip-path="url(#c)"/>"#),
    TreeChangeCase(
      testDescription: "removing a gradient before another one with its ID",
      before: #"<defs><linearGradient k="1" id="g"><stop stop-color="red"/></linearGradient>"#
        + #"<linearGradient id="g"><stop stop-color="lime"/></linearGradient></defs>"#
        + #"<rect width="50" height="50" fill="url(#g)"/>"#,
      edits: [.remove("1")],
      after: #"<defs><linearGradient id="g"><stop stop-color="lime"/></linearGradient></defs>"#
        + #"<rect width="50" height="50" fill="url(#g)"/>"#),
    TreeChangeCase(
      testDescription: "moving a mask into a clip path, where it masks nothing",
      before: #"<defs k="defs"><mask k="m" id="m"><rect width="20" height="20" fill="white"/></mask>"#
        + #"<clipPath k="c" id="c"><rect width="40" height="40"/></clipPath></defs>"#
        + #"<rect width="50" height="50" fill="lime" mask="url(#m)"/>"#,
      edits: [.move("m", into: "c", at: 0)],
      after: #"<defs k="defs"><clipPath k="c" id="c"><mask k="m" id="m"><rect width="20" height="20" fill="white"/>"#
        + #"</mask><rect width="40" height="40"/></clipPath></defs>"#
        + #"<rect width="50" height="50" fill="lime" mask="url(#m)"/>"#),
    TreeChangeCase(
      testDescription: "inserting a marker, a pattern and a filter",
      before: #"<defs k="defs"/><path d="M10 10 L50 50" stroke="black" marker-end="url(#mk)"/>"#
        + #"<rect x="50" width="40" height="40" fill="url(#p)" filter="url(#f)"/>"#,
      edits: [
        .insert("marker", ["id": "mk", "k": "mk", "markerWidth": "4", "markerHeight": "4"], into: "defs", at: 0),
        .insert("rect", ["width": "4", "height": "4", "fill": "red"], into: "mk", at: 0),
        .insert(
          "pattern", ["id": "p", "k": "p", "width": "10", "height": "10", "patternUnits": "userSpaceOnUse"],
          into: "defs", at: 1),
        .insert("rect", ["width": "5", "height": "5", "fill": "blue"], into: "p", at: 0),
        .insert("filter", ["id": "f", "k": "f"], into: "defs", at: 2),
        .insert("feOffset", ["dx": "3"], into: "f", at: 0),
      ],
      after: #"<defs k="defs"><marker id="mk" k="mk" markerWidth="4" markerHeight="4">"#
        + #"<rect width="4" height="4" fill="red"/></marker>"#
        + #"<pattern id="p" k="p" width="10" height="10" patternUnits="userSpaceOnUse">"#
        + #"<rect width="5" height="5" fill="blue"/></pattern><filter id="f" k="f"><feOffset dx="3"/></filter></defs>"#
        + #"<path d="M10 10 L50 50" stroke="black" marker-end="url(#mk)"/>"#
        + #"<rect x="50" width="40" height="40" fill="url(#p)" filter="url(#f)"/>"#),
    TreeChangeCase(
      testDescription: "replacing the spans of a text with character data",
      before: ##"<text k="t" y="20">a<tspan id="s" fill="red">b</tspan></text><use href="#s" y="40"/>"##,
      edits: [.setText("t", "xyz")],
      after: ##"<text k="t" y="20">xyz</text><use href="#s" y="40"/>"##),
    TreeChangeCase(
      testDescription: "inserting an animation in a document without animations",
      before: #"<rect k="r" width="50" height="50" fill="red"/>"#,
      edits: [.insert("set", ["attributeName": "fill", "to": "lime"], into: "r", at: 0)],
      after: #"<rect k="r" width="50" height="50" fill="red"><set attributeName="fill" to="lime"/></rect>"#),
    TreeChangeCase(
      testDescription: "inserting the element that an animation changes",
      before: ##"<set href="#late" attributeName="fill" to="lime"/><g k="g"/>"##,
      edits: [.insert("rect", ["id": "late", "width": "50", "height": "50", "fill": "red"], into: "g", at: 0)],
      after: ##"<set href="#late" attributeName="fill" to="lime"/><g k="g"><rect id="late" width="50" height="50" fill="red"/></g>"##),
  ]

  @Test("the context of a changed tree is the context of the document written with the changes", arguments: cases)
  func changedContext(_ change: TreeChangeCase) async throws {
    let base = parse(change.before)
    let (tree, changes) = try base.document.editing(change.edits)
    let changed = base.changing(to: tree, changes: changes)
    let written = parse(change.after)
    #expect(changed.isAnimated == written.isAnimated)
    #expect(changed.animations.smil.count == written.animations.smil.count)
    // The tables find the elements of the changed tree, as the ones of the written document do.
    #expect(Set(changed.contents.keys) == Set((changed.root?.elements ?? []).map(\.index)))
    #expect(changed.contents.allSatisfy { $0.key == $0.value.index })
    func attributes(_ element: any SVGElement) -> [String: String] { element.base.attributes }
    #expect(Set(changed.contentIdMap.keys) == Set(written.contentIdMap.keys))
    for name in changed.contentIdMap.keys {
      #expect(changed[name].map(attributes) == written[name].map(attributes), "\(name)")
      #expect(changed[name].map { changed.contents[$0.index] != nil } ?? true, "\(name)")
    }
    #expect(changed.pservers.mapValues(attributes) == written.pservers.mapValues(attributes))
    #expect(changed.clipPaths.mapValues(attributes) == written.clipPaths.mapValues(attributes))
    #expect(changed.masks.mapValues(attributes) == written.masks.mapValues(attributes))
    #expect(changed.patterns.mapValues(attributes) == written.patterns.mapValues(attributes))
    #expect(changed.filters.mapValues(attributes) == written.filters.mapValues(attributes))
    #expect(changed.markers.mapValues(attributes) == written.markers.mapValues(attributes))
    // The tables hold the elements of the changed tree, not the ones that it replaced.
    let elements = Set((changed.root?.elements ?? []).map(\.index))
    for element in [
      changed.pservers.values.map(\.index), changed.clipPaths.values.map(\.index), changed.masks.values.map(\.index),
      changed.patterns.values.map(\.index), changed.filters.values.map(\.index), changed.markers.values.map(\.index),
    ].joined() {
      #expect(elements.contains(element))
    }
    for time in [0, 0.5] {
      #expect(try await pixels(of: changed.at(time: time)) == pixels(of: written.at(time: time)), "at \(time)")
    }
  }
}
