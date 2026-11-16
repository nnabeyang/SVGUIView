import Foundation
import Testing

@testable import SVGCore

/// A document with the content.
private func parse(_ content: String) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8))
}

/// A change of a document, as the document API records it.
enum NodeChangeStep: Sendable {
  /// Edits of the tree.
  case edits([TreeEdit])
  /// Attributes to set or remove, by the `k` attributes of the elements.
  case attributes([String: [String: String?]])
}

/// Changes of a document, which a view renders together after rendering the document before them.
struct NodeChange: Sendable, CustomTestStringConvertible {
  let testDescription: String
  let before: String
  let steps: [NodeChangeStep]
}

extension DocumentTree {
  /// The element whose `k` attribute is the key.
  fileprivate func element(withKey key: String) throws -> ElementID {
    func find(_ element: DocumentElement) -> ElementID? {
      if element.attributes["k"] == key { return element.id }
      return element.children.lazy.compactMap(find).first
    }
    return try #require(root.flatMap(find), "The document has no element \(key)")
  }
}

extension SVGBaseContext {
  /// The context with a change made, and the elements that the change makes again, as a view records them.
  fileprivate func changing(by step: NodeChangeStep) throws -> (SVGBaseContext, ChangedElements) {
    switch step {
    case .edits(let edits):
      let (tree, changes) = try document.editing(edits)
      let changed = changing(to: tree, changes: changes)
      return (changed, changed.changedElements(by: changes))
    case .attributes(let attributes):
      var values = [ElementID: [String: String?]]()
      for (key, attributes) in attributes {
        values[try document.element(withKey: key)] = attributes
      }
      var changes = DocumentChanges()
      changes.attributes = Set(values.keys)
      changes.paintingAttributes = Set(values.filter { $0.value.keys.contains { $0 != "transform" } }.keys)
      changes.identifiers = Set(values.filter { $0.value.keys.contains("id") }.keys)
      let changed = changing(to: document.changingAttributes(values), changes: changes)
      return (changed, changed.changedElements(by: changes))
    }
  }
}

@Suite("The render nodes that changes of a document change")
struct ChangedNodesTests {
  static let changes: [NodeChange] =
    TreeChangeContextTests.cases.map {
      NodeChange(testDescription: $0.testDescription, before: $0.before, steps: [.edits($0.edits)])
    } + [
      NodeChange(
        testDescription: "changing the ID of a shape to the one that a use element shows",
        before: ##"<rect k="r" id="a" width="10" height="10"/><rect k="s" id="b" x="20" width="10" height="10"/>"##
          + ##"<use href="#b" y="50"/><use href="#a" x="50"/>"##,
        steps: [.attributes(["r": ["id": "b"]])]),
      NodeChange(
        testDescription: "the fill of a shape that a use element shows",
        before: ##"<g><rect k="r" id="a" width="10" height="10" fill="red"/></g><use href="#a" x="50"/>"##
          + #"<rect x="20" width="10" height="10"/>"#,
        steps: [.attributes(["r": ["fill": "lime"]])]),
      NodeChange(
        testDescription: "a stop of a gradient that a shape in a group is painted with",
        before: #"<defs><linearGradient id="g"><stop k="s" stop-color="red"/></linearGradient></defs>"#
          + #"<g><rect width="50" height="50" fill="url(#g)"/></g><rect x="60" width="10" height="10"/>"#,
        steps: [.attributes(["s": ["stop-color": "lime"]])]),
      NodeChange(
        testDescription: "the transform of a shape that a use element shows",
        before: ##"<rect k="r" id="a" width="10" height="10"/><use href="#a" x="50"/>"##,
        steps: [.attributes(["r": ["transform": "translate(5 5)"]])]),
      NodeChange(
        testDescription: "removing a group with a shape that a use element shows",
        before: ##"<g k="g"><g><rect id="a" width="10" height="10"/></g></g><use href="#a" x="50"/>"##
          + #"<rect k="b" id="b" x="20" width="10" height="10"/>"#,
        steps: [.edits([.remove("g")])]),
      NodeChange(
        testDescription: "moving a shape painted with a gradient into another group",
        before: #"<defs><linearGradient id="g"><stop stop-color="red"/></linearGradient></defs>"#
          + #"<g k="g"><rect k="r" id="r" width="10" height="10" fill="url(#g)"/></g><g k="h"/>"#
          + ##"<use href="#r" y="50"/>"##,
        steps: [.edits([.move("r", into: "h", at: 0)])]),
      NodeChange(
        testDescription: "inserting a shape, and then giving it the ID that a use element shows",
        before: ##"<g k="g"><rect id="a" width="10" height="10" fill="red"/></g><use href="#a" x="50"/>"##,
        steps: [
          .edits([.insert("rect", ["k": "n", "width": "20", "height": "20"], into: "g", at: 0)]),
          .attributes(["n": ["id": "a"]]),
        ]),
      NodeChange(
        testDescription: "changing the fill of a shape, and then removing the gradient that it was painted with",
        before: #"<defs><linearGradient k="1" id="g"><stop stop-color="red"/></linearGradient></defs>"#
          + #"<rect k="r" width="50" height="50" fill="url(#g)"/><rect id="o" x="60" width="10" height="10"/>"#,
        steps: [.attributes(["r": ["fill": "url(#g) blue"]]), .edits([.remove("1")])]),
      NodeChange(
        testDescription: "a shape in a document with an animation",
        before: #"<rect k="r" width="10" height="10"><set attributeName="fill" to="lime"/></rect>"#
          + ##"<use href="#x"/><rect id="x" x="20" width="10" height="10"/>"##,
        steps: [.attributes(["r": ["width": "20"]])]),
    ]

  @Test("the nodes found from the changed subtrees are the ones found in the whole tree", arguments: changes)
  func sameNodes(_ change: NodeChange) throws {
    let shown = parse(change.before)
    // The context that a view shows found its references when it rendered changes before.
    _ = shown.changedNodesInWholeTree(since: shown, by: ChangedElements())
    var context = shown
    var elements = ChangedElements()
    for step in change.steps {
      let (changed, changedElements) = try context.changing(by: step)
      context = changed
      elements.formUnion(changedElements)
    }
    let found = try #require(context.changedNodes(since: shown, by: elements))
    let references = try #require(context.elementReferences.references)
    let expected = try #require(context.changedNodesInWholeTree(since: shown, by: elements))
    #expect(found.nodes == expected.nodes)
    #expect(found.painting == expected.painting)
    #expect(found.reordered == expected.reordered)
    // The references of the changed context are the ones of its whole tree.
    #expect(references == context.elementReferences.references)
    if !context.isAnimated {
      #expect(SVGBaseContext.treeChanges(from: shown.root, to: context.root) != nil)
    }
  }

  @Test("a context that hasn't found its references finds the nodes in the whole tree")
  func withoutReferences() throws {
    let shown = parse(##"<g k="g"><rect id="a" width="10" height="10"/></g><use href="#a" x="50"/>"##)
    let (context, elements) = try shown.changing(by: .edits([.remove("g")]))
    #expect(shown.elementReferences.references == nil)
    let found = try #require(context.changedNodes(since: shown, by: elements))
    let expected = try #require(context.changedNodesInWholeTree(since: shown, by: elements))
    #expect(found.nodes == expected.nodes)
    #expect(found.painting == expected.painting)
    #expect(context.elementReferences.references != nil)
  }
}
